`timescale 1ns/1ps
module tb_cic;
	reg clk = 0, reset = 1; always #10 clk = ~clk;
	reg strobe = 0; reg signed [15:0] din = 0;
	wire ov; wire signed [15:0] od;
	CicDecimator #(.IN_W(16), .R_LOG2(4)) dut(.clk(clk), .reset(reset), .inValid(strobe), .inData(din), .outValid(ov), .outData(od));
	reg signed [15:0] aud [0:107420]; integer n, f;
	initial begin
		$readmemh("../sim/audio_d3.hex", aud); f = $fopen("../sim/cic_out.txt", "w");
		repeat (5) @(posedge clk); reset = 0;
		for (n = 0; n < 20000; n = n + 1) begin
			din <= aud[n]; strobe <= 1; @(posedge clk); strobe <= 0; repeat (15) @(posedge clk);
		end
		$fclose(f); $finish;
	end
	always @(posedge clk) if (ov) $fdisplay(f, "%0d", od);
endmodule
