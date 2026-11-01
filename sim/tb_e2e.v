`timescale 1ns/1ps
// End-to-end: raw audio samples -> CIC -> feeder -> FFT stand-in -> detector -> mapper.
// The strobe interval is shortened (512 clk instead of 1024) to keep the run time reasonable;
// the design only requires > 256 clk/sample so that decimated samples are > 4096 clocks apart.
module tb_e2e;
	parameter NS = 107000;
	reg clk = 0, reset = 1;
	always #10 clk = ~clk;
	reg sampleStrobe = 0;
	reg signed [15:0] sampleIn = 0;
	wire signalValid, tick;
	wire [6:0] midi; wire signed [14:0] cents16; wire [2:0] stringIdx; wire [13:0] hz10;
	TunerCore #(.PAUSE_CLKS(20000)) dut
	(.clk(clk), .reset(reset), .sampleStrobe(sampleStrobe), .sampleIn(sampleIn), .sens(2'd0), .stringMode(1'b0), .fs32(1'b0),
	 .signalValid(signalValid), .midi(midi), .cents16(cents16), .stringIdx(stringIdx), .hz10(hz10), .tick(tick));

	reg signed [15:0] aud [0:NS-1];
	integer n, fcic, nres = 0;
	initial begin
		$readmemh("../sim/audio_d3.hex", aud);
		fcic = $fopen("../sim/cic_out.txt", "w");
		dut.fft0.calc_en = 0;                        // skip the slow FFT while the buffer fills
		repeat (20) @(posedge clk);
		reset = 0;
		for (n = 0; n < NS; n = n + 1) begin
			sampleIn <= aud[n]; sampleStrobe <= 1; @(posedge clk); sampleStrobe <= 0;
			repeat (511) @(posedge clk);
			if (n == 100500) dut.fft0.calc_en = 1;   // buffer (4096 decimated = 65536 audio samples) is full
		end
		repeat (3) @(posedge tick);
		$display("DONE"); $fclose(fcic); $finish;
	end
	always @(posedge clk) if (dut.cicValid) $fdisplay(fcic, "%0d", dut.cicData);
	always @(posedge tick) begin
		nres = nres + 1;
		if (dut.fft0.calc_en) $display("%0t frame %0d: valid=%0d midi=%0d cents=%0.2f hz=%0.2f string=%0d", $time, nres, signalValid, midi, $itor(cents16)/16.0, $itor(hz10)/10.0, stringIdx);
	end
endmodule
