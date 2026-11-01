// VGA 1024x768@70Hz tuner screen, drawn in 8x8-pixel "blocks" (128 x 96 grid):
//   top    : six string indicators  E A d G b E
//   middle : big note letter (+ sharp mark, octave)
//   gauge  : -50..+50 cents, 1 block per cent, needle + in-tune zone, flat/sharp arrows
//   bottom : frequency in Hz
// All dynamic inputs come from the 50 MHz domain; they are double-registered and latched during vertical blanking.
module TunerRaster
(
	input pixClk,
	input reset,
	input dValid,                       // a pitch is available
	input [4:0] dLetter,                // 10..16 = A b C d E F G
	input dSharp,
	input [3:0] dOctave,
	input signed [7:0] dCents,          // -50..+50
	input [2:0] dString,                // 0..5, 7 = none
	input [15:0] dBcd,                  // Hz*10 as 4 BCD digits {hundreds, tens, units, tenths}
	output hSync,
	output vSync,
	output blankN,
	output reg [7:0] rOut,
	output reg [7:0] gOut,
	output reg [7:0] bOut
);
	// ---------------------------------------------------------------- timing
	wire hs0, vs0, blank0;
	wire [9:0] xPix, yPix;
	VGASyncGenerator sg0 (.reset(reset), .inClock(pixClk), .vSync(vs0), .hSync(hs0), .blank(blank0), .xPixel(xPix), .yPixel(yPix));

	// ---------------------------------------------------------------- CDC + latch in vertical blanking
	reg        v1, v2, lValid, lSharp;
	reg [4:0]  l1, l2, lLetter;
	reg [3:0]  o1, o2, lOct;
	reg signed [7:0] c1, c2, lC;
	reg [2:0]  s1, s2, lStr;
	reg [15:0] b1, b2, lBcd;
	reg        sh1, sh2;
	always @(posedge pixClk)
	begin
		v1 <= dValid; v2 <= v1;  l1 <= dLetter; l2 <= l1;  sh1 <= dSharp; sh2 <= sh1;
		o1 <= dOctave; o2 <= o1;  c1 <= dCents; c2 <= c1;  s1 <= dString; s2 <= s1;  b1 <= dBcd; b2 <= b1;
		if (blank0 && xPix == 10'd0 && yPix == 10'd0)
		begin
			lValid <= v2; lLetter <= l2; lSharp <= sh2; lOct <= o2; lC <= c2; lStr <= s2; lBcd <= b2;
		end
	end

	// ---------------------------------------------------------------- stage A: register coordinates
	reg [7:0] xs, ys;
	reg hsA, vsA, blA;
	always @(posedge pixClk)
	begin
		xs <= {1'b0, xPix[9:3]};
		ys <= {1'b0, yPix[9:3]};
		hsA <= hs0; vsA <= vs0; blA <= blank0;
	end

	// ---------------------------------------------------------------- helpers
	function [6:0] segMask(input [4:0] code);     // {g,f,e,d,c,b,a}
		case (code)
			5'd0: segMask = 7'b0111111; 5'd1: segMask = 7'b0000110; 5'd2: segMask = 7'b1011011;
			5'd3: segMask = 7'b1001111; 5'd4: segMask = 7'b1100110; 5'd5: segMask = 7'b1101101;
			5'd6: segMask = 7'b1111101; 5'd7: segMask = 7'b0000111; 5'd8: segMask = 7'b1111111;
			5'd9: segMask = 7'b1101111;
			5'd10: segMask = 7'b1110111;  // A
			5'd11: segMask = 7'b1111100;  // b
			5'd12: segMask = 7'b0111001;  // C
			5'd13: segMask = 7'b1011110;  // d
			5'd14: segMask = 7'b1111001;  // E
			5'd15: segMask = 7'b1110001;  // F
			5'd16: segMask = 7'b0111101;  // G
			default: segMask = 7'b0000000;
		endcase
	endfunction

	function glyph(input [7:0] x, input [7:0] y, input [7:0] x0, input [7:0] y0,
	               input [7:0] w, input [7:0] h, input [7:0] t, input [6:0] m);
		reg [7:0] rx, ry, half, th;
		begin
			rx = x - x0; ry = y - y0; half = h >> 1; th = t >> 1;
			glyph = 1'b0;
			if (x >= x0 && y >= y0 && rx < w && ry < h)
			begin
				if (m[0] && ry < t && rx >= t && rx < w - t)                          glyph = 1'b1;  // a
				if (m[1] && rx >= w - t && ry < half + th)                            glyph = 1'b1;  // b
				if (m[2] && rx >= w - t && ry + th >= half)                           glyph = 1'b1;  // c
				if (m[3] && ry + t >= h && rx >= t && rx < w - t)                     glyph = 1'b1;  // d
				if (m[4] && rx < t && ry + th >= half)                                glyph = 1'b1;  // e
				if (m[5] && rx < t && ry < half + th)                                 glyph = 1'b1;  // f
				if (m[6] && ry + th >= half && ry + th < half + t && rx >= t && rx < w - t) glyph = 1'b1;  // g
			end
		end
	endfunction

	function [7:0] absDiff8(input [7:0] a, input [7:0] b);
		absDiff8 = (a > b) ? (a - b) : (b - a);
	endfunction

	// ---------------------------------------------------------------- colours
	localparam [23:0] C_BG = 24'h10151B, C_DIM = 24'h3C424C, C_WHITE = 24'hF2F4F8, C_GREEN = 24'h19E06A,
	                  C_YEL = 24'hFFC800, C_RED = 24'hF03C32, C_ZONE = 24'h0C3A22, C_GRID = 24'h8C96A0,
	                  C_CYAN = 24'h78C8E6, C_BOX = 24'h3C5064, C_BOXTXT = 24'h96AABE, C_BOXON = 24'h1EA050;

	// ---------------------------------------------------------------- stage B: colour
	wire signed [7:0] cI = lC;
	wire [7:0] cAbs = cI[7] ? (~cI + 1'b1) : cI;
	wire inTune = (cAbs <= 8'd5);
	wire [7:0] needleX = 8'd64 + cI;
	wire [3:0] dH = lBcd[15:12], dT = lBcd[11:8], dU = lBcd[7:4], dF = lBcd[3:0];

	reg [23:0] col;
	reg hsB, vsB, blB;
	reg [7:0] t8;
	reg [2:0] si;
	reg on;
	reg [23:0] sCol, tCol;

	always @(posedge pixClk)
	begin
		hsB <= hsA; vsB <= vsA; blB <= blA;
		col = C_BG;

		// ---- gauge background: in-tune zone, baseline, ticks
		if (xs >= 8'd59 && xs <= 8'd69 && ys >= 8'd62 && ys < 8'd82) col = C_ZONE;
		if (ys == 8'd71 && xs >= 8'd14 && xs <= 8'd114) col = C_GRID;
		if (xs >= 8'd14 && xs <= 8'd114 &&
		    (xs == 8'd14 || xs == 8'd24 || xs == 8'd34 || xs == 8'd44 || xs == 8'd54 || xs == 8'd64 ||
		     xs == 8'd74 || xs == 8'd84 || xs == 8'd94 || xs == 8'd104 || xs == 8'd114) &&
		    ((ys >= 8'd62 && ys < 8'd82) || (xs == 8'd64 && ys >= 8'd58 && ys < 8'd86)))
			col = C_GRID;

		// ---- flat / sharp arrows
		if (xs >= 8'd3 && xs <= 8'd12 && absDiff8(ys, 8'd72) <= xs - 8'd3)
			col = (lValid && cI[7] && !inTune) ? C_RED : C_DIM;
		if (xs >= 8'd115 && xs <= 8'd124 && absDiff8(ys, 8'd72) <= 8'd124 - xs)
			col = (lValid && !cI[7] && !inTune) ? C_RED : C_DIM;

		// ---- needle
		if (lValid && absDiff8(xs, needleX) <= 8'd1 && ys >= 8'd58 && ys < 8'd86)
			col = inTune ? C_GREEN : ((cAbs <= 8'd15) ? C_YEL : C_RED);

		// ---- big note letter
		tCol = !lValid ? C_DIM : (inTune ? C_GREEN : C_WHITE);
		if (glyph(xs, ys, 8'd41, 8'd17, 8'd28, 8'd40, 8'd7, segMask(lLetter))) col = tCol;

		// ---- sharp mark '#': two vertical + two horizontal bars
		if (lValid && lSharp && xs >= 8'd73 && xs < 8'd87 && ys >= 8'd17 && ys < 8'd33)
		begin
			t8 = xs - 8'd73;
			if ((t8 >= 8'd3 && t8 < 8'd5) || (t8 >= 8'd9 && t8 < 8'd11) ||
			    (ys - 8'd17 >= 8'd5 && ys - 8'd17 < 8'd7) || (ys - 8'd17 >= 8'd10 && ys - 8'd17 < 8'd12))
				col = tCol;
		end

		// ---- octave digit
		if (lValid && glyph(xs, ys, 8'd73, 8'd36, 8'd12, 8'd21, 8'd3, segMask({1'b0, lOct}))) col = tCol;

		// ---- frequency readout  "XXX.X"
		if (lValid)
		begin
			if (dH != 4'd0 && glyph(xs, ys, 8'd44, 8'd86, 8'd5, 8'd8, 8'd1, segMask({1'b0, dH}))) col = C_CYAN;
			if ((dH != 4'd0 || dT != 4'd0) && glyph(xs, ys, 8'd51, 8'd86, 8'd5, 8'd8, 8'd1, segMask({1'b0, dT}))) col = C_CYAN;
			if (glyph(xs, ys, 8'd58, 8'd86, 8'd5, 8'd8, 8'd1, segMask({1'b0, dU}))) col = C_CYAN;
			if (xs == 8'd65 && ys == 8'd93) col = C_CYAN;
			if (glyph(xs, ys, 8'd67, 8'd86, 8'd5, 8'd8, 8'd1, segMask({1'b0, dF}))) col = C_CYAN;
		end

		// ---- string indicators  E A d G b E
		if (ys >= 8'd3 && ys < 8'd13 && xs >= 8'd29 && xs < 8'd101)
		begin
			si = (xs < 8'd41) ? 3'd0 : (xs < 8'd53) ? 3'd1 : (xs < 8'd65) ? 3'd2 :
			     (xs < 8'd77) ? 3'd3 : (xs < 8'd89) ? 3'd4 : 3'd5;
			t8 = 8'd29 + {5'd0, si} * 8'd12;                    // box left edge
			if (xs >= t8 && xs < t8 + 8'd10)
			begin
				on = lValid && (lStr == si);
				// outline / fill
				if (on) col = C_BOXON;
				else if (xs == t8 || xs == t8 + 8'd9 || ys == 8'd3 || ys == 8'd12) col = C_BOX;
				// label
				sCol = on ? 24'h08140C : C_BOXTXT;
				case (si)
					3'd0, 3'd5: if (glyph(xs, ys, t8 + 8'd2, 8'd4, 8'd6, 8'd8, 8'd1, segMask(5'd14))) col = sCol;
					3'd1:       if (glyph(xs, ys, t8 + 8'd2, 8'd4, 8'd6, 8'd8, 8'd1, segMask(5'd10))) col = sCol;
					3'd2:       if (glyph(xs, ys, t8 + 8'd2, 8'd4, 8'd6, 8'd8, 8'd1, segMask(5'd13))) col = sCol;
					3'd3:       if (glyph(xs, ys, t8 + 8'd2, 8'd4, 8'd6, 8'd8, 8'd1, segMask(5'd16))) col = sCol;
					default:    if (glyph(xs, ys, t8 + 8'd2, 8'd4, 8'd6, 8'd8, 8'd1, segMask(5'd11))) col = sCol;
				endcase
			end
		end

		col = blA ? 24'h000000 : col;
		{rOut, gOut, bOut} <= col;
	end

	assign hSync = hsB;
	assign vSync = vsB;
	assign blankN = ~blB;
endmodule
