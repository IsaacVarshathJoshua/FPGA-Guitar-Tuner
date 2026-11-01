// 7-segment decoder for the DE2-115 displays (active low outputs, seg[0]=a ... seg[6]=g)
// code: 0..9 digits, 10 A, 11 b, 12 C, 13 d, 14 E, 15 F, 16 G, 17 '-', 19 sharp mark, others blank
module Seg7(input [4:0] code, output reg [6:0] seg);
	always @*
		case (code)
			5'd0: seg = ~7'b0111111; 5'd1: seg = ~7'b0000110; 5'd2: seg = ~7'b1011011; 5'd3: seg = ~7'b1001111;
			5'd4: seg = ~7'b1100110; 5'd5: seg = ~7'b1101101; 5'd6: seg = ~7'b1111101; 5'd7: seg = ~7'b0000111;
			5'd8: seg = ~7'b1111111; 5'd9: seg = ~7'b1101111;
			5'd10: seg = ~7'b1110111; 5'd11: seg = ~7'b1111100; 5'd12: seg = ~7'b0111001; 5'd13: seg = ~7'b1011110;
			5'd14: seg = ~7'b1111001; 5'd15: seg = ~7'b1110001; 5'd16: seg = ~7'b0111101;
			5'd17: seg = ~7'b1000000;
			5'd19: seg = ~7'b1100011;
			default: seg = 7'b1111111;
		endcase
endmodule
