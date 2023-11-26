// Server.default = Server.remote(\organelle, NetAddr("localhost", 57110), o)
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
	recvPort:4000
);

//KNOBS////////////////
/*
Knob values are saved to server-side control buses!
get a knob value by using (for example) ~knobs[0].get or In.kr(0, 1) or Bus(\control, 0, 1).get
*/

~knobs = Bus.control(numChannels: 6);


OSCdef( \OrganelleKnobs,
	{
		arg msg, time, addr, recvPort;
		var knobs, val;
		if (s.serverRunning) {
		knobs = ~knobs.getnSynchronous(6);
		knobs.do {
			|current, index|
			val = msg[index+1] / 1023;
				if (val != current) {
					Bus(\control, ~knobs.index + index).setSynchronous(val);
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

OSCdef( \footswitch,
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
~vuBus = Array.newClear(4);
4.do{|i|
	~vuBus.put(i, Bus.control);
	};

// ~updateVU = {
// 	|array, peakInt|
// 	var levels, tmp;
// 	levels = Array.newClear(4);
// 	array.do{ |bus, i|
// 		tmp = (bus.getSynchronous * 11).asInteger;
// 		levels.put(i, tmp);
// 	};
// 	m.sendMsg("/oled/vumeter", levels[2], levels[3], levels[0], levels[1], peakInt);
// };

OSCdef( \rcvPeakRMS,
	{
		arg msg, time, addr, recvPort;
		var index, rms, peak, peakbits = 0;

		index = msg[2];
		peak = msg[3].ampdb.linlin(-80, 0, 0, 1);
		rms = msg[4].ampdb.linlin(-80, 0, 0, 1);

		//format("peak: %", peak).postln;
		~vuBus[index].setSynchronous( rms );

		if ( peak > 0.99 ){
			peakbits.setBit(index + 4, true);
		}{
			peakbits.setBit(index + 4, false);
		};

		//rotate bitmask so that peaks line up with Organelle UI:Out1, Out2, In1, In2 --->>> In1, In2, Out1, Out2
		peakbits = peakbits.asBinaryDigits[4..7].rotate(2);
		peakbits = peakbits.sum({|bit, i|
			bit * 2.pow(3-i);
		});

		//~updateVU.value(~vuBus, peakbits);

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
			var buses, sigs;
			buses = Array.newClear(4);
			sigs = Array.newClear(4);
			4.do { |i|
				buses.put(i, Bus(rate: \audio, index: i, numChannels: 1));
				sigs.put(i, In.ar(buses[i], 1));
				SendPeakRMS.kr(
					sig: sigs[i],
					cmdName: '/rcvPeakRMS',
					replyID: i
				);
			}
		}).add.play
	)
});

//x = {SinOsc.ar * In.kr(0).linlin(0,1,0,5)}.play
//x.free
//s.freeAll