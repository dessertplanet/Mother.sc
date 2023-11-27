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
~loadingMessage = "/Patch/mother.scd";
m.sendMsg("/oled/line/1", ~loadingMessage);

/*
OSC Handling
Organelle OSC inbound messages
    /key ii 10 100
    /knobs iiiiii 604 342 451 64 666 1023
    /quit
    /fs  i 1

not implement yet
    /footSwitchPolarity
    /enc i 1
    /encbut i 1
    /midich

notes:
aux key = 0, C = 1 (and midi = 60)
knobs 1-4 = pots, 5 = volume , 6 = expr pedal
enc = 1 = clockwise, 0 anti
*/

OSCdef( \RouteAux,
	{

		arg msg, time, addr, recvPort;

		if(msg[1] == 0){
			~self.sendMsg("/aux", msg[2]);
		}{
			~self.sendMsg("/note", msg[1] + 59, msg[2] / 3 );
		}
	},
	"/key",
	recvPort:4000
);

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
		//define this in your patch! Use the ~knobs[0-6] buses to getSynchronous and setSynchronous these values.
	},
	"/knobs",
	recvPort:4000
);


/*
Knob values are saved to server-side control buses!
get a knob value by using (for example) ~knobsBus[0].get or In.kr(0, 1) or Bus(\control, 0, 1).get
*/

~knobsBus = Bus.control(numChannels: 6);
~knobs = 6.collect({ |i| Bus(\control, ~knobsBus.index + i) });

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
					if (index == 4) {
						s.volume.volume = val.ampdb;
					}
				}
			}
		}
	},
	"/knobs",
	recvPort:4000
);

//Encoder behavior is weird- you need to enable submenu for the messages to even be sent. most patches don't use this at all. TODO!
//not defined here!	"/enc"
//not defined here!	"/encbut"


//Write footswitch state to a control bus. For most pedals 0 =

~fs = Bus.control;

OSCdef( \BusFS,
	{
		arg msg, time, addr, recvPort;
		~fs.setSynchronous(msg[1]);
	},
	"/fs",
	recvPort:4000
);

//Gracefully shutdown the SuperCollider server when the kill-patch script is run
OSCdef( \KillPatch,
	{
		arg msg, time, addr, recvPort;
		s.quit;
	},
	"/quit"
);

//VUMeter///////
//Setup control bus for VU meter
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

//Setup MIDI, pulling device from Organelle settings in /sdcard/patch_loaded.sh
~setupMIDI = {
	var patch_loaded, lines, devicesetting, sources;

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

~ioBus = Bus(rate: \audio, index: 0, numChannels: 4);

// configure and boot the server
s.options.bindAddress = "0.0.0.0";
s.waitForBoot({
	(
		s.volume.lag = 0.1;
		s.volume.volume = 0.2.ampdb;
		//s.volume.volume = 0.1.ampdb;
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










