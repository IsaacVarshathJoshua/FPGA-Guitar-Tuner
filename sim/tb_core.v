`timescale 1ns/1ps
// Full TunerCore test. The decimated-sample buffer is pre-loaded (tools/make_vectors.py produces the
// bit-exact CIC output); a second short test pushes raw 48.8 kHz samples through the CIC.
module tb_core;
	reg clk = 0, reset = 1;
	always #10 clk = ~clk;                       // 50 MHz

	reg sampleStrobe = 0;
	reg signed [15:0] sampleIn = 0;
	reg [1:0] sens = 2'd0;
	reg stringMode = 1'b0;
	wire signalValid, tick;
	wire [6:0] midi; wire signed [14:0] cents16; wire [2:0] stringIdx; wire [13:0] hz10;

	TunerCore #(.PAUSE_CLKS(20000)) dut
	(.clk(clk), .reset(reset), .sampleStrobe(sampleStrobe), .sampleIn(sampleIn), .sens(sens), .stringMode(stringMode), .fs32(1'b0),
	 .signalValid(signalValid), .midi(midi), .cents16(cents16), .stringIdx(stringIdx), .hz10(hz10), .tick(tick));

	integer j, nres = 0;
	reg [255:0] vecfile;
	reg signed [15:0] vec [0:4095];
	integer expectMidi, expectC16;
	reg [8*40-1:0] label;

	always @(posedge tick) begin
		nres = nres + 1;
		$display("%0t  frame %0d: valid=%0d midi=%0d cents=%0.2f hz=%0.1f string=%0d  (detPos=%0d found=%0d)",
		         $time, nres, signalValid, midi, $itor(cents16)/16.0, $itor(hz10)/10.0, stringIdx, dut.detPos, dut.detFound);
	end

	initial begin
		if (!$value$plusargs("VEC=%s", vecfile)) vecfile = "sim/vec_e2.hex";
		$readmemh(vecfile, vec);
		repeat (20) @(posedge clk);
		reset = 0;
		// pre-load the circular sample buffer (hierarchical write)
		for (j = 0; j < 4096; j = j + 1) dut.fed0.ram[j] = vec[j];
		if ($test$plusargs("STRINGMODE")) stringMode = 1;
		// run ~10 measurement frames
		repeat (10) @(posedge tick);
		$display("DONE");
		$finish;
	end
	initial begin #3000000000; $display("TIMEOUT"); $finish; end
endmodule
