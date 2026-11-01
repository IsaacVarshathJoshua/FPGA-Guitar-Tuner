// Sequential unsigned restoring divider: quot = num / den, NW clocks. den must be non-zero.
module DivSeq #(parameter NW = 32, parameter DW = 20)
(
	input clk,
	input reset,
	input start,
	input [NW-1:0] num,
	input [DW-1:0] den,
	output reg done,                    // 1-clk pulse
	output reg [NW-1:0] quot
);
	reg [NW-1:0] q;
	reg [DW-1:0] rem;
	reg [DW-1:0] d;
	reg [7:0] cnt;
	reg busy;
	wire [DW:0] remSh = {rem, q[NW-1]};

	always @(posedge clk)
	begin
		done <= 1'b0;
		if (reset) begin busy <= 1'b0; quot <= 0; end
		else if (start && !busy)
		begin
			busy <= 1'b1; q <= num; rem <= 0; d <= den; cnt <= NW;
		end
		else if (busy)
		begin
			if (remSh >= {1'b0, d}) begin rem <= remSh - {1'b0, d}; q <= {q[NW-2:0], 1'b1}; end
			else                    begin rem <= remSh[DW-1:0];      q <= {q[NW-2:0], 1'b0}; end
			cnt <= cnt - 1'b1;
			if (cnt == 8'd1)
			begin
				busy <= 1'b0; done <= 1'b1;
				quot <= remSh >= {1'b0, d} ? {q[NW-2:0], 1'b1} : {q[NW-2:0], 1'b0};
			end
		end
	end
endmodule
