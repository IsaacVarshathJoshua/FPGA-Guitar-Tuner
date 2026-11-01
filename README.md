# FPGA Guitar Tuner (DE2-115, Quartus II 13.0)

Built on top of the FFTVisualizer project (codec I2C/I2S, VGA timing, 4096-pt FFT MegaCore are reused).

## Open it
1. Quartus II 13.0 -> File > Open Project -> `Verilog/GuitarTuner.qpf`
2. Processing > Start Compilation, then program `output_files/GuitarTuner.sof`.
3. Keep `hann4096.hex` in the `Verilog/` folder (project root).

## Controls
| Control | Function |
|---|---|
| KEY[0] | reset (re-configures the codec) |
| SW[17] | 1 = MIC jack, 0 = LINE-IN jack (read at reset) |
| SW[16] | codec channel 1 = left, 0 = right |
| SW[15:14] | input threshold, 00 = most sensitive |
| SW[13] | unused - the tuner is now always in guitar-string mode (E A D G B E only) |
| SW[12] | HEX shows frequency (0.1 Hz) instead of note + cents |
| SW[11] | +20 dB mic boost |
Outputs: VGA screen (string row, big note, cents needle, Hz), HEX7..0, LEDR bar (left = flat, right = sharp, 5 cents/LED), LEDG[7:0] in-tune lamp, LEDG[8] heartbeat.

## Signal chain
audio 48 828.125 Hz -> CIC4 /16 (3051.76 Hz) -> circular buffer + Hann window -> 4096-pt FFT (0.745 Hz/bin)
-> spectrum RAM -> Harmonic Product Spectrum (k = 80..580, i.e. 60-432 Hz) -> Hann ratio interpolation
-> nearest note/string -> cents = 3462.468*(f-fn)/(f+fn). New reading about every 85 ms, window ~1.3 s.

## What was verified (simulation only, iverilog)
* CIC decimator: bit-exact against the Python model.
* Full TunerCore with a behavioural FFT stand-in (`sim/FFT_mf_sim.v`): synthetic guitar notes E2 -12c, A2 +8c, G3 -30c, E4 +3c, weak-fundamental E2 +20c -> all read within 0.12 cent, correct note and string.
* Python model (`tools/proto.py`, `stress.py`) incl. noise and 50 Hz hum: mean error 0.1-0.2 cent; rare gross errors only with very low level + strong hum.
* Whole design compiles in iverilog; VGA screen rendered (`docs/screen_preview.png`).

## NOT verified (no Quartus / board here)
* Quartus compile, timing, pin behaviour and the real FFT MegaCore. Please compile and send me any error text.
* FFT output order: assumed natural (as the original used it). If note readings look wrong, set `BIT_REVERSED(1)` in `TunerCore.v`.
* FFT MegaCore uses OpenCore Plus evaluation: the programmed design may stop after a time limit unless licensed.
* Real guitar signals, mic gain, and the SW[17] codec changes were only checked by reading the WM8731 register map.
Regenerate tables with `python3 tools/gen_tables.py` (run from this folder).

## Changes (v2)
* **Sample-rate bug fixed.** The codec was running at 32.552 kHz (12.5 MHz/384) while the design assumed 48.828 kHz, so every reading was exactly 1.5x too high
  (A3 -> E4, B3 -> F#4, C4 -> G4, G3 -> D4) and notes above ~288 Hz fell outside the search range. Two fixes:
  1. `CodecConfigurator` now writes the Sampling Control register (R8 = 0, normal mode, 256fs) -> 48.828 kHz.
  2. `GuitarTuner.v` measures CLOCK_50 clocks per audio frame (1024 or 1536) and `TunerCore` rescales the result by 2/3 if the codec is still at 32.552 kHz.
* HPS search range widened to ~60-477 Hz (440 Hz now reads 440.0 Hz). Score changed to HPS-3, |X[k]|*(|X[2k]|+|X[k]|/32)*(|X[3k]|+|X[k]|/32): works for pure sines (tone generator) and for a weak fundamental (low E2 on a small mic was read as D3/B3 = its 2nd/3rd harmonic with the older 2-harmonic score).
* Always string mode: any note is mapped to the nearest of E2 A2 D3 G3 B3 E4. HEX shows the string note + cents (up to 250, 3 digits). '-' = string is flat (tune up), blank = sharp (tune down).
* Within +-5 cents the cents field shows 0 and the green LEDs light ("no correction").
