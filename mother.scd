// mother host output
// Server.default = Server.remote(\organelle, NetAddr(~mother, 57110), o)

~motherHostname = "localhost";
~langPort = 57120;
~serverPort = 57110;
~organelleListenPort = 4001;
~organelleSendPort = 4000;

m = NetAddr(~motherHostname, ~organelleListenPort);

m.sendMsg("/patchLoaded",1);
m.sendMsg("/oled/setscreen",3);

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
	recvPort:~organelleSendPort
);

OSCdef( \OrganelleKnobs,
	{
		arg msg, time, addr, recvPort;
		var val;
		val = (msg[5]/1023).ampdb;
		s.volume.volume = val;
	},
	"/knobs",
	recvPort:~organelleSendPort
);

OSCdef( \OrganelleEncTurn,
	{
		arg msg, time, addr, recvPort;
	},
	"/enc",
	recvPort:~organelleSendPort
);

OSCdef( \OrganelleEncBut,
	{
		arg msg, time, addr, recvPort;
	},
	"/encbut",
	recvPort:~organelleSendPort
);

OSCdef( \OrganelleFootSwitch,
	{
		arg msg, time, addr, recvPort;

	},
	"/fs",
	recvPort:~organelleSendPort
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



