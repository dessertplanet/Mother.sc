// Server.default = Server.remote(\organelle, NetAddr("localhost", 57110), o)

~mainPatch = "/tmp/patch/main.scd".standardizePath;

//Environment variables
~mother = "localhost";

//Env variable for organelle destination (use for screen, led, OS communication)
m = NetAddr(~mother, 4001);

//Env variable for sending messages back to sclang
~self = NetAddr(~mother, 57120);

m.sendMsg("/patchLoaded",1);
m.sendMsg("/oled/setscreen",3);

//Display a helpful message to indicate this is an SC patch
~loadingMessage = "/System/mother.scd";
m.sendMsg("/oled/line/1", ~loadingMessage);

/////OSCdefs with recvPort: 4000 are parsing inputs from Organelle's physical hardware. These are processed (to varying degrees) and then send back to sclang for consistency and remote accessibility.

OSCdef( \RoutePhysicalKeys,
	{

		arg msg, time, addr, recvPort;

		if(msg[1] == 0){
			~self.sendMsg("/aux", msg[2]);
		}{
			//notes from the physical organelle keyboard are transposed so that the low C on organelle is middle C
			~self.sendMsg("/note", msg[1] + 59, msg[2] / 3 );
		}
	},
	"/key",
	recvPort:4000
);

OSCdef( \RouteFS,
	{
		arg msg, time, addr, recvPort;
		msg = [ "/fs" ] ++ msg;
		~self.sendMsg(*msg);
	},
	"/fs",
	recvPort:4000
);

/*
Knob values are saved to server-side control buses!
get a knob value by using (for example) ~knobsBus[0].get or In.kr(0, 1) or Bus(\control, 0, 1).get
*/

~knobsBus = Bus.control(numChannels: 6);
~knobs = 6.collect({ |i| Bus(\control, ~knobsBus.index + i) });

//6 knobs: 4 main knobs on the left, Master Volume knob, Exp input is also treated like a knob (FS and Exp data are BOTH calculated from the "pedal" input on Organelle

OSCdef( \BusKnobs,
	{
		arg msg, time, addr, recvPort;
		var knobs, val;
		if (s.serverRunning) {
		knobs = ~knobsBus.getnSynchronous(6);
		knobs.do {
			|current, index|
			val = msg[index+1] / 1023;
				if (val != current) {
					~knobs[index].setSynchronous(val);
					~self.sendMsg("/knobs", index, val);
					if (index == 4) {
						//Knob index 4 is the main volume knob- so we apply that automatically to the master server volume
						s.volume.volume = val.ampdb;
					}
				}
			}
		}
	},
	"/knobs",
	recvPort:4000
);

/////OSCdefs with recvPort: 57120 are for messages received by sclang from local hardware or remote messages. These are mostly prototyped here as examples and typically live in your main.scd

OSCdef( \aux,
	{
		arg msg, time, addr, recvPort;
		//define this in your patch
	},
	"/aux",
	recvPort:57120
);

OSCdef( \note,
	{
		arg msg, time, addr, recvPort;
		//define this in your patch
	},
	"/note",
	recvPort:57120
);

OSCdef( \knobs,
	{
		arg msg, time, addr, recvPort;

		/*define this in your patch! Use the ~knobs[0-6] buses to getSynchronous and setSynchronous these values.
		Note you may not even need the above args here, the trigger of a knob change and the values on buses could be enough*/
	},
	"/knobs",
	recvPort:57120
);

//Encoder behavior is weird- you need to enable submenu for the messages to even be sent. most patches don't use this at all. TODO!
//not defined here!	"/enc"
//not defined here!	"/encbut"

//VUMeter/////// This section recieves data from the OrganelleIO synth that is created when the server boots, and then parses that data and sends it to the Organelle UI in a way it understands so that the input and output VUmeters work.

~vuBus = Bus.control(numChannels: 4);
~vuVals = 0 ! 4;
~peakbits = 0;

OSCdef( \rcvPeakRMS,
	{
		arg msg, time, addr, recvPort;
		var replyId, bus, rms, peak, message;

		replyId = msg[2];
		peak = msg[3].ampdb.linlin(-80, 0, 0, 1);
		rms = msg[4].ampdb.linlin(-80, 0, 0, 1);

		//format("peak: %", peak).postln;
		bus = Bus(\control, ~vuBus.index + replyId);
		bus.setSynchronous ( rms );

		if (peak > 0.9){
			~peakbits = ~peakbits.setBit(replyId, true)
		}{
			~peakbits = ~peakbits.setBit(replyId, false)
		};

		if (s.serverRunning) {
			~vuVals = ~vuBus.getnSynchronous(4);
			message = [ "/oled/vumeter" ]  ++ (~vuVals*12).asInteger ++ [ ~peakbits ];
			m.sendMsg(*message);
		}
	},
	"/rcvPeakRMS",
	recvPort: 57120
);

///////MIDI
//Setup MIDI, pulling device from Organelle settings in /sdcard/patch_loaded.sh
~setupMIDI = {
	var patch_loaded, lines, devicesetting, sources;

	//this function is called once the server is booted.

	patch_loaded = File("/sdcard/patch_loaded.sh", "r");

	lines = patch_loaded.readAllString.split($\n);

	lines.do({arg item;
		if(item.beginsWith("# midiDevice"), {
			devicesetting = item.split($,).at(1).split($:).at(0);
		});
	});

	MIDIClient.init(1,1,false);

	sources = MIDIClient.sources;

	sources.do({arg item;
		if(item.device == devicesetting, {
			MIDIIn.connect(0, MIDIIn.findPort(item.device, item.name));
		});
	});
};

MIDIdef.noteOn(\midiNoteOn, {
	| vel, note |
	~self.sendMsg("/note", note, vel)
});

MIDIdef.noteOff(\midiNoteOff, {
	| vel, note |
	~self.sendMsg("/note", note, 0)
});


/////System level things

//This gracefully shuts down the SuperCollider server when the kill-patch script is run
OSCdef( \KillPatch,
	{
		arg msg, time, addr, recvPort;
		s.quit;
	},
	"/quit"
);

///////Server config and boot

~ioBus = Bus(rate: \audio, index: 0, numChannels: 4);

s.options.bindAddress = "0.0.0.0";
s.waitForBoot({
	(
		s.volume.lag = 0.1;
		s.volume.volume = 0.2.ampdb;
		~setupMIDI.();

		SynthDef(\OrganelleIO, {

			[2,3,0,1].do {
				|input, i|
				SendPeakRMS.kr(
					sig: ~ioBus.ar[input],
					cmdName: '/rcvPeakRMS',
					peakLag: 4,
					replyID: i;
				);
			}

		}).add.play;

		m.sendMsg("/oled/line/1", "...ready");

		~mainPatch.load;
	)
});