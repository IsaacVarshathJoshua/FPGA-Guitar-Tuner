// Captures the positive-frequency half (bins 0..2047) of one complete FFT frame into RAM.
// BIT_REVERSED=1 if the megacore is set to bit-reversed output order.
module SpectrumCapture #(parameter BIT_REVERSED = 0)
(
	input clk,
	input reset,
	input arm,                         // pulse: capture the next complete frame
	input srcValid,
	input srcSop,
	input srcEop,
	input [15:0] srcRe,
	input [15:0] srcIm,
	output reg done,                   // 1-clk pulse when the frame is stored
	input [10:0] rdAddr,
	output reg [15:0] rdRe,
	output reg [15:0] rdIm
);
	reg [31:0] ram [0:2047];
	reg [11:0] idx;
	reg armed, capturing;

	function [11:0] bitrev12(input [11:0] v);
		integer b;
		begin
			for (b = 0; b < 12; b = b + 1) bitrev12[b] = v[11-b];
		end
	endfunction

	wire [11:0] curIdx = srcSop ? 12'd0 : idx;      // the sop sample is index 0
	wire [11:0] binIdx = BIT_REVERSED ? bitrev12(curIdx) : curIdx;

	always @(posedge clk)
	begin
		done <= 1'b0;
		if (reset)
		begin
			armed <= 1'b0; capturing <= 1'b0; idx <= 12'd0;
		end
		else
		begin
			if (arm) armed <= 1'b1;

			if (srcValid)
			begin
				if (srcSop && armed) begin capturing <= 1'b1; armed <= 1'b0; end

				if ((capturing || (srcSop && armed)))
				begin
					if (binIdx[11] == 1'b0) ram[binIdx[10:0]] <= {srcRe, srcIm};
					idx <= curIdx + 1'b1;
					if (srcEop)
					begin
						capturing <= 1'b0;
						done <= 1'b1;
					end
				end
				else idx <= curIdx + 1'b1;
			end
		end
	end

	always @(posedge clk)
		{rdRe, rdIm} <= ram[rdAddr];
endmodule
