// Server.default = Server.remote(\organelle, NetAddr(~mother, 57110), o)

//Environment variables
~motherHostname = "localhost";
~langPort = 57120;
~serverPort = 57110;
~organelleListenPort = 4001;
~organelleHWPort = 4000;

//Env variable for organelle destination (use for screen, led, OS communication)
m = NetAddr(~motherHostname, ~organelleListenPort);

m.sendMsg("/patchLoaded",1);
m.sendMsg("/oled/setscreen",3);

//Display a helpful message to indicate this is an SC patch
~loadingMessage = "/Path/mother.scd";
m.sendMsg("/oled/line/1", ~loadingMessage);

~knobs = ();

5.do { |i|
	~knobs.put(i.asSymbol, Bus.control(s, 1));
}

/*
Knobs are saved to control buses!
*/
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

OSCdef( \OrganelleKnobs,
	{
		arg msg, time, addr, recvPort;
		var val;
		~knobs.do {
			|i, bus|
			val = msg[i+1] / 1023;
			if (val != bus.getSynchronous) {
				bus.set(val);
				if (i == 4) {
					s.volume.volume = val.ampdb;
				}
			}
		}
	},
	"/knobs",
	recvPort:~organelleHWPort
);

OSCdef( \OrganelleEncTurn,
	{
		arg msg, time, addr, recvPort;
	},
	"/enc",
	recvPort:~organelleHWPort
);

OSCdef( \OrganelleEncBut,
	{
		arg msg, time, addr, recvPort;
	},
	"/encbut",
	recvPort:~organelleHWPort
);

OSCdef( \OrganelleFootSwitch,
	{
		arg msg, time, addr, recvPort;

	},
	"/fs",
	recvPort:~organelleHWPort
);

OSCdef( \OrganelleAudioLevel,
	{
		arg msg, time, addr, recvPort;
		msg.postln;
	},
	"/audioLevel"
);

OSCdef( \KillPatch,
	{
		arg msg, time, addr, recvPort;

		if ( msg[1]>0,
			{s.quit;}
		);
	},
	"/quit"
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
        // Removed routine here
		m.sendMsg("/oled/line/1","remote server ready");
		m.sendMsg("/led", 2);
		s.volume.lag = 0.2;
		~setupMIDI.();
	)
});


///TESTING

///{SinOsc.ar(mul: 0.2)}.play



