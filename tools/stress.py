from proto import *
rng = np.random.default_rng(7)
R = 16
strings = [82.407, 110.0, 146.832, 195.998, 246.942, 329.628]
for peak, noise, hum in ((4000, 20, 0), (1000, 200, 0), (600, 100, 150), (300, 100, 100)):
    gross = 0; errs = []; tot = 0
    for f in strings:
        for det in (-30, 0, 30):
            f0 = f*2**(det/1200)
            x = guitar(f0, peak=peak, noise=noise, rng=rng).astype(float)
            t = np.arange(len(x))/FS_IN
            x += hum*np.sin(2*np.pi*50*t) + 0.5*hum*np.sin(2*np.pi*100*t) + 0.3*hum*np.sin(2*np.pi*150*t)
            est = detect(cic4(np.round(x).astype(np.int64), R), R); tot += 1
            e = cents(est, f0)
            if abs(e) > 100: gross += 1
            else: errs.append(abs(e))
    print(f"peak={peak:5d} noise={noise:4d} hum50={hum:4d}: gross={gross}/{tot}  mean|err|={np.mean(errs) if errs else float('nan'):.2f}c max={np.max(errs) if errs else float('nan'):.2f}c")
