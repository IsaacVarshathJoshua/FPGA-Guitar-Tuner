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

## note
Project execution requires the FFT IP created via the updated Quartus Prime, configured according to the specifications mentioned in the FFT IP Verilog.


