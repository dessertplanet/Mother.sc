//Based on TheTechnobear's Simple Poly!

~cutoff = 5000;
~voices = nil ! 128;

~updateOLED = { m.sendMsg("/oled/line/1", format("Cutoff %", ~cutoff.asInteger)) };
~updateOLED.();

OSCdef(\notes,
	{
		arg msg, time, addr, recvPort;
		var note, vel;
		note = msg[1];
		vel = msg[2];

		if (vel > 0){
			~voices[note] = Synth(\testSynth, [
				freq: note.midicps,
				cutoff: ~cutoff,
				amp: vel/127 * 0.3 ])
		}{
			~voices[note].set(\gate, 0);
			~voices[note] = nil;
		}
	},
	"/note",
	recvPort: NetAddr.langPort
);

OSCdef(\knobs,
	{
		~cutoff = ~knobs[0].getSynchronous.linexp(0,1, 50, 20000).clip(10, 24000);
		~voices.do(
			{ |voice|
				voice.set(\cutoff, ~cutoff);
		});
		~updateOLED.();
	},
	"/knobs",
	recvPort: NetAddr.langPort
);

SynthDef(\testSynth,
	{
		var sig,env;
		sig = Saw.ar(\freq.kr(440));
		env = EnvGen.ar(Env.adsr(),\gate.kr(1),doneAction:2);
		sig = sig * env * \amp.ir(0.01);
		sig = LPF.ar(sig, \cutoff.ar(val: 5000, lag: 0.2));
		Out.ar(\out.ir(0),sig!2);
}).add;

