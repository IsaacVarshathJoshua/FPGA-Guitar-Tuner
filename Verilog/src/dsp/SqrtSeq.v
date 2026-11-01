// Sequential integer square root (digit-by-digit). root = floor(sqrt(rad)); takes RW/2 clocks.
module SqrtSeq #(parameter RW = 36)
(
	input clk,
	input reset,
	input start,
	input [RW-1:0] rad,
	output reg done,                    // 1-clk pulse
	output reg [RW/2-1:0] root
);
	localparam HW = RW>>1;
	reg [RW-1:0] r;
	reg [HW+3:0] rem;
	reg [7:0] cnt;
	reg busy;

	wire [HW+3:0] remN  = {rem[HW+1:0], r[RW-1:RW-2]};
	wire [HW+3:0] trial = {2'b00, root, 2'b01};

	always @(posedge clk)
	begin
		done <= 1'b0;
		if (reset) begin busy <= 1'b0; root <= 0; end
		else if (start && !busy)
		begin
			busy <= 1'b1; r <= rad; rem <= 0; root <= 0; cnt <= HW;
		end
		else if (busy)
		begin
			r <= {r[RW-3:0], 2'b00};
			if (remN >= trial) begin rem <= remN - trial; root <= {root[HW-2:0], 1'b1}; end
			else               begin rem <= remN;         root <= {root[HW-2:0], 1'b0}; end
			cnt <= cnt - 1'b1;
			if (cnt == 8'd1) begin busy <= 1'b0; done <= 1'b1; end
		end
	end
endmodule
