// Sequential double-dabble binary -> BCD converter (W bits in, D decimal digits out)
module Bin2Bcd #(parameter W = 14, parameter D = 4)
(
	input clk,
	input reset,
	input start,
	input [W-1:0] bin,
	output reg done,
	output reg [4*D-1:0] bcd
);
	reg [W+4*D-1:0] sh;
	reg [4:0] cnt;
	reg busy;
	wire [4*D-1:0] dig = sh[W+4*D-1:W];
	reg [4*D-1:0] adj;
	integer i;
	always @*
		for (i = 0; i < D; i = i + 1)
			adj[4*i +: 4] = (dig[4*i +: 4] >= 4'd5) ? dig[4*i +: 4] + 4'd3 : dig[4*i +: 4];

	always @(posedge clk)
	begin
		done <= 1'b0;
		if (reset) busy <= 1'b0;
		else if (start && !busy) begin sh <= {{(4*D){1'b0}}, bin}; cnt <= W; busy <= 1'b1; end
		else if (busy)
		begin
			sh <= {adj, sh[W-1:0]} << 1;
			cnt <= cnt - 1'b1;
			if (cnt == 5'd1) begin busy <= 1'b0; done <= 1'b1; end
		end
	end
	always @(posedge clk) if (done) bcd <= sh[W+4*D-1:W];
endmodule
