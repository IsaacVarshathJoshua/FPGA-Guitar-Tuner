#!/usr/bin/env python3
"""sim/audio_*.hex : raw 16-bit audio at 48 828.125 Hz for the end-to-end simulation."""
import numpy as np
from proto import *
rng = np.random.default_rng(11)
f0 = 146.832*2**(-18/1200)          # D3, 18 cents flat
x = guitar(f0, dur=2.2, peak=3000, noise=20, rng=rng)
with open("../sim/audio_d3.hex", "w") as f:
    for v in x: f.write(f"{int(v) & 0xFFFF:04X}\n")
np.save("audio_d3.npy", x)
print(len(x), "samples, f0 =", f0)
