#!/usr/bin/env python3
"""Bit-level-ish Python model of the FPGA guitar-tuner DSP chain.
Used to pick parameters (decimation, window, HPS, interpolation) before writing Verilog.
Chain: 16-bit audio @48828.125 Hz -> CIC4 /R -> Hann(4096) -> FFT4096 (16-bit BFP) ->
       HPS-2 search -> Hann-ratio peak interpolation -> note/cents.
"""
import numpy as np, sys
FS_IN = 50e6/1024
N = 4096

def cic4(x, R):
    """Integer CIC, order 4, decimate by R, output scaled back to 16 bit (matches Verilog plan)."""
    W = 16 + 4*int(np.log2(R))
    mask = (1 << W) - 1
    x = x.astype(np.int64)
    acc = x.copy()
    for _ in range(4):               # integrators (modulo arithmetic)
        acc = np.cumsum(acc) & mask
    acc = acc[R-1::R]
    for _ in range(4):               # combs
        acc = (acc - np.concatenate(([0], acc[:-1]))) & mask
    acc = np.where(acc >= (1 << (W-1)), acc - (1 << W), acc)   # signed wrap
    return (acc >> (4*int(np.log2(R)))).astype(np.int64)

def guitar(f0, dur=3.0, amps=(1, .8, .5, .3, .2, .1), B=1e-4, tau=1.5, noise=20, peak=4000, rng=None):
    rng = rng or np.random.default_rng()
    t = np.arange(int(dur*FS_IN))/FS_IN
    y = np.zeros_like(t)
    for n, a in enumerate(amps, 1):
        fn = n*f0*np.sqrt(1 + B*n*n)
        y += a*np.exp(-t/(tau/ (1+0.3*(n-1))))*np.sin(2*np.pi*fn*t + rng.uniform(0, 6.28))
    y = y/np.max(np.abs(y))*peak + rng.normal(0, noise, len(t))
    return np.round(y).astype(np.int64)

def hann16():
    n = np.arange(N)
    return np.round(0.5*(1 - np.cos(2*np.pi*n/N))*65535).astype(np.int64)

def fft_bfp(xw):
    X = np.fft.fft(xw.astype(float))
    m = max(np.max(np.abs(X.real)), np.max(np.abs(X.imag)))
    s = 2.0**np.ceil(np.log2(m/32767.0)) if m > 0 else 1.0
    return np.round(X.real/s), np.round(X.imag/s)

def detect(xdec, R, klo=80, khi=580):
    fs_d = FS_IN/R
    xw = (xdec[-N:]*hann16()) >> 16
    re, im = fft_bfp(xw)
    M = np.sqrt(re*re + im*im)[:2048]
    ks = np.arange(klo, khi+1)
    score = M[ks]*M[2*ks]
    kb = ks[np.argmax(score)]
    w = M[kb-3:kb+4]; kp = kb-3+np.argmax(w[1:6])+1
    a = M[kp]; up = M[kp+1] >= M[kp-1]
    b = M[kp+1] if up else M[kp-1]
    d = (2*b - a)/(a + b); d = min(max(d, 0), 0.5)
    pos = kp + (d if up else -d)
    return pos*fs_d/N

def cents(f, ref): return 1200*np.log2(f/ref)

if __name__ == "__main__":
    R = int(sys.argv[1]) if len(sys.argv) > 1 else 16
    rng = np.random.default_rng(1)
    strings = [82.407, 110.0, 146.832, 195.998, 246.942, 329.628]
    for label, amps in (("normal harmonics", (1, .8, .5, .3, .2, .1)),
                        ("weak fundamental", (.25, 1, .7, .4, .25, .1))):
        errs = []; octs = 0; tot = 0
        for f in strings:
            for det in (-40, -15, -3, 0, 3, 15, 40):
                f0 = f*2**(det/1200)
                x = guitar(f0, amps=amps, rng=rng)
                xd = cic4(x, R)
                est = detect(xd, R)
                e = cents(est, f0); tot += 1
                if abs(e) > 100: octs += 1
                else: errs.append(abs(e))
        print(f"R={R:2d} Fs_d={FS_IN/R:8.2f} bin={FS_IN/R/N:.4f} Hz | {label:17s} | n={tot} gross errors={octs} "
              f"| mean|err|={np.mean(errs):.2f}c  max={np.max(errs):.2f}c")
