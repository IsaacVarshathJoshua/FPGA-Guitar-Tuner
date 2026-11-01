// 4th-order CIC decimator (sinc^4), multiplier-free.
// 48.828 kHz audio -> /2^R_LOG2 -> (R_LOG2=4) 3051.76 Hz. Gain is normalised back to unity.
module CicDecimator #(parameter IN_W = 16, parameter R_LOG2 = 4)
(
	input clk,
	input reset,
	input inValid,                       // 1-clk strobe at the input rate
	input signed [IN_W-1:0] inData,
	output reg outValid,                 // 1-clk strobe at the output rate
	output reg signed [IN_W-1:0] outData
);
	localparam ORDER = 4;
	localparam W = IN_W + ORDER*R_LOG2;  // register width (modulo arithmetic, wrap-around is intended)

	reg signed [W-1:0] i1, i2, i3, i4;
	reg signed [W-1:0] d1, d2, d3, d4;
	reg signed [W-1:0] c;
	reg [R_LOG2-1:0] cnt;
	reg [2:0] stage;

	always @(posedge clk)
	begin
		outValid <= 1'b0;

		if (reset)
		begin
			i1 <= 0; i2 <= 0; i3 <= 0; i4 <= 0;
			d1 <= 0; d2 <= 0; d3 <= 0; d4 <= 0;
			c <= 0; cnt <= 0; stage <= 0; outData <= 0;
		end
		else
		begin
			if (inValid)
			begin
				i1 <= i1 + {{(W-IN_W){inData[IN_W-1]}}, inData};
				i2 <= i2 + i1;
				i3 <= i3 + i2;
				i4 <= i4 + i3;
				cnt <= cnt + 1'b1;
				if (cnt == {R_LOG2{1'b1}})
				begin
					c <= i4;          // take the integrator output, then run the 4 combs over 4 clocks
					stage <= 3'd1;
				end
			end

			case (stage)
				3'd1: begin c <= c - d1; d1 <= c; stage <= 3'd2; end
				3'd2: begin c <= c - d2; d2 <= c; stage <= 3'd3; end
				3'd3: begin c <= c - d3; d3 <= c; stage <= 3'd4; end
				3'd4: begin c <= c - d4; d4 <= c; stage <= 3'd5; end
				3'd5: begin
					outData  <= c[W-1 -: IN_W];   // divide by CIC gain 2^(ORDER*R_LOG2)
					outValid <= 1'b1;
					stage    <= 3'd0;
				end
				default: ;
			endcase
		end
	end
endmodule
