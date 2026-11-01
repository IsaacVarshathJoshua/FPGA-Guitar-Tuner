`timescale 1ns/1ps
// Renders one VGA frame of the tuner screen to a PPM file with fixed display values.
module tb_top;
	reg pc = 0; always #7 pc = ~pc;
	reg reset = 1;
	wire hs, vs, bn; wire [7:0] r, g, b;
	TunerRaster ras(.pixClk(pc), .reset(reset), .dValid(1'b1), .dLetter(5'd10), .dSharp(1'b0), .dOctave(4'd2), .dCents(-8'sd12),
	  .dString(3'd1), .dBcd(16'h1094), .hSync(hs), .vSync(vs), .blankN(bn), .rOut(r), .gOut(g), .bOut(b));
	integer f, i;
	reg [23:0] img [0:1024*768-1];
	reg [9:0] x1, x2, y1, y2; reg b1, b2;
	reg grab = 0;
	always @(posedge pc) begin
		x1 <= ras.xPix; y1 <= ras.yPix; b1 <= ras.blank0; x2 <= x1; y2 <= y1; b2 <= b1;
		if (grab && !b2 && x2 < 1024) img[y2*1024 + x2] <= {r, g, b};
	end
	initial begin
		repeat (4) @(posedge pc); reset = 0;
		@(negedge vs); @(negedge vs); grab = 1;
		@(negedge vs); grab = 0;
		f = $fopen("../sim/screen.ppm", "w"); $fdisplay(f, "P3\n1024 768\n255");
		for (i = 0; i < 1024*768; i = i + 1) $fdisplay(f, "%0d %0d %0d", img[i][23:16], img[i][15:8], img[i][7:0]);
		$fclose(f); $finish;
	end
endmodule
