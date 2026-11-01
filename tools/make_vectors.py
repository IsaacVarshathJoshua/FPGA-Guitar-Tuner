#!/usr/bin/env python3
"""Creates sim/vec_*.hex : the last 4096 decimated samples (bit-exact CIC model) of a synthetic guitar note."""
import sys, numpy as np
from proto import *
rng = np.random.default_rng(3)
cases = {"e2": 82.407*2**(-12/1200), "a2": 110.0*2**(8/1200), "g3": 195.998*2**(-30/1200), "e4": 329.628*2**(3/1200),
         "weak_e2": 82.407*2**(20/1200)}
for name, f0 in cases.items():
    amps = (.25, 1, .7, .4, .25, .1) if name.startswith("weak") else (1, .8, .5, .3, .2, .1)
    x = guitar(f0, amps=amps, peak=3000, noise=20, rng=rng)
    xd = cic4(x, 16)[-4096:]
    with open(f"../sim/vec_{name}.hex", "w") as f:
        for v in xd: f.write(f"{int(v) & 0xFFFF:04X}\n")
    print(f"{name}: f0={f0:.4f} Hz  (midi-relative cents shown by sim)")
