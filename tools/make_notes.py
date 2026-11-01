#!/usr/bin/env python3
"""Creates sim/notes_all.hex, notes_freq.hex, notes_names.hex for tb_tuner_notes.v
(run from GuitarTuner/tools :  python3 make_notes.py).  Same synthetic-guitar + bit-exact CIC chain as make_vectors.py."""
import numpy as np
from proto import guitar, cic4
S = {"E2": 82.41, "A2": 110.00, "D3": 146.83, "G3": 196.00, "B3": 246.94, "E4": 329.63}
cases  = [(f"{n} open string", f) for n, f in S.items()]
cases += [("E2 flat  -25c", S["E2"]*2**(-25/1200)), ("A2 sharp +30c", S["A2"]*2**(30/1200)),
          ("D3 flat  -15c", S["D3"]*2**(-15/1200)), ("G3 sharp +12c", S["G3"]*2**(12/1200)),
          ("B3 flat  -40c", S["B3"]*2**(-40/1200)), ("E4 sharp +20c", S["E4"]*2**(20/1200))]
cases += [("wrong: 70.00 Hz", 70.00), ("wrong: F2  87.31", 87.31), ("wrong: G2  98.00", 98.00),
          ("wrong: C3 130.81", 130.81), ("wrong: G#3 207.65", 207.65), ("wrong: C4 261.63", 261.63),
          ("wrong: A4 440.00", 440.00)]
rng = np.random.default_rng(7)
with open("../sim/notes_all.hex", "w") as fa, open("../sim/notes_freq.hex", "w") as ff, open("../sim/notes_names.hex", "w") as fn:
    for name, f0 in cases:
        x = guitar(f0, amps=(1, .8, .5, .3, .2, .1), peak=3000, noise=20, rng=rng)
        for v in cic4(x, 16)[-4096:]: fa.write(f"{int(v) & 0xFFFF:04X}\n")
        ff.write(f"{int(round(f0*1000)):08X}\n")                       # Hz * 1000
        fn.write(name.ljust(18)[:18].encode().hex().upper() + "\n")     # 18 chars
print("cases:", len(cases))
