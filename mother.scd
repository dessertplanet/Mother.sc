// Server.default = Server.remote(\organelle, NetAddr(~motherHostName, ~serverPort), o)
//Environment variables
~motherHostname = "localhost";
//~motherHostname = "organellem.local"
~langPort = 57120;
~serverPort = 57110;
~organelleListenPort = 4001;
~organelleHWPort = 4000;

//Env variable for organelle destination (use for screen, led, OS communication)
m = NetAddr(~motherHostname, ~organelleListenPort);

//Env variable for sending messages back to sclang
~self = NetAddr(~motherHostname, ~langPort);

m.sendMsg("/patchLoaded",1);
m.sendMsg("/oled/setscreen",3);

//Display a helpful message to indicate this is an SC patch
~loadingMessage = "/Path/mother.scd";
m.sendMsg("/oled/line/1", ~loadingMessage);




/*
OSC Handling
Organelle OSC inbound messages
    /key ii 10 100
    /knobs iiiiii 604 342 451 64 666 1023
    /enc i 1
    /encbut i 1
    /fs  i 1

not implement yet
    /footSwitchPolarity
    /quit
    /midich

notes:
aux key = 0, C = 1 (and midi = 60)
knobs 1-4 = pots, 5 = volume , 6 = expr pedal
enc = 1 = clockwise, 0 anti
*/

OSCdef( \OrganelleKeys,
	{

		arg msg, time, addr, recvPort;

		//KEY STUFF JERE
	},
	"/key",
	recvPort:~organelleHWPort
);

//KNOBS////////////////
/*
Knob values are saved to server-side control buses!
get a knob value by using (for example) ~knobs[0].get or In.kr(0, 1) or Bus(\control, 0, 1).get
*/
~knobs = Array.newClear(5);
5.do { |i|
	~knobs.put(i, Bus.control(server: s, numChannels: 1));
};


OSCdef( \OrganelleKnobs,
	{
		arg msg, time, addr, recvPort;
		var val, bus;
		5.do {
			|i|
			val = msg[i+1] / 1023;
			bus = ~knobs[i];
			if (s.serverRunning) {
				if (val != bus.getSynchronous) {
					bus.set(val);
					if (i == 4) {
						s.volume.volume = val.ampdb;
					}
				}
			}
		}
	},
	"/knobs",
	recvPort:~organelleHWPort
);

//not defined here!	"/enc"
//not defined here!	"/encbut"
//not defined here!	"/fs"


OSCdef( \KillPatch,
	{
		arg msg, time, addr, recvPort;

		if ( msg[1]>0,
			{s.quit;}
		);
	},
	"/quit"
);

OSCdef( \rcvPeakRMS,
	{
		arg msg, time, addr, recvPort;
		msg.postln;
	},
	"/rcvPeakRMS",
	recvPort: ~langPort
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

// configure and boot the server
s.options.bindAddress = "0.0.0.0";
s.waitForBoot({
	(
		m.sendMsg("/oled/line/1","remote server ready");
		m.sendMsg("/led", 2);
		s.volume.lag = 0.2;
		s.volume.volume = 0.1.ampdb;
		~setupMIDI.();

		SynthDef(\OrganelleIO, {
			var sigLR, insigLR, busLR, inbusLR;
			busLR = Bus(rate: \audio, index: 0, numChannels: 2);
			inbusLR = Bus(rate: \audio, index: 2, numChannels: 2);

			sigLR = In.ar(busLR, 2);
			insigLR = In.ar(inbusLR, 2);

			SendPeakRMS.kr(
				sig: sigLR,
				cmdName: '/rcvPeakRMS'
			);
		}).add.play
	)
});



