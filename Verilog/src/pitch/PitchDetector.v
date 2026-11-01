// Pitch detector working on the captured spectrum RAM.
//  1. Harmonic Product Spectrum (HPS-3): score(k) = |X[k]| * (|X[2k]|+|X[k]|/32) * (|X[3k]|+|X[k]|/32), k = kLo..kHi
//     (3 harmonics so a weak fundamental, e.g. low E2 on a small mic, is not mistaken for its 2nd/3rd harmonic;
//      for k > 682 the 3k bin is outside the 2048-bin spectrum and |X[2k]| is used instead)
//  2. Local peak refinement around the HPS winner (+-2 bins)
//  3. Hann-window ratio interpolation:  d = (2r-1)/(r+1),  r = |X[kp+-1]| / |X[kp]|  (exact for a Hann-windowed tone)
// Result: pos = (kp + d) * 256   (frequency in units of 1/256 FFT bin)
module PitchDetector
(
	input clk,
	input reset,
	input go,                             // pulse: spectrum RAM holds a fresh frame
	input [10:0] kLo,                     // HPS search range in FFT bins (kHi*2 must stay < 2048)
	input [9:0]  kHi,
	output reg [10:0] rdAddr,
	input [15:0] rdRe,
	input [15:0] rdIm,
	output reg done,                      // 1-clk pulse
	output reg found,                     // peak looks plausible
	output reg [17:0] pos
);
	// ---------------------------------------------------------------- magnitude unit
	reg        magReq;
	reg [10:0] magAddr;
	reg        magDone;
	reg [17:0] magVal;          // 4 * |X[k]|  (2 extra fractional bits)

	reg [2:0]  ms;
	reg [31:0] psum;
	wire       sqStart = (ms == 3'd3);
	wire       sqDone;
	wire [17:0] sqRoot;

	SqrtSeq #(.RW(36)) sq0 (.clk(clk), .reset(reset), .start(sqStart), .rad({psum, 4'b0000}), .done(sqDone), .root(sqRoot));

	wire signed [15:0] sRe = rdRe;
	wire signed [15:0] sIm = rdIm;

	always @(posedge clk)
	begin
		magDone <= 1'b0;
		if (reset) ms <= 3'd0;
		else case (ms)
			3'd0: if (magReq) begin rdAddr <= magAddr; ms <= 3'd1; end
			3'd1: ms <= 3'd2;                                   // RAM read latency
			3'd2: begin psum <= sRe*sRe + sIm*sIm; ms <= 3'd3; end
			3'd3: ms <= 3'd4;                                   // sqrt starts here
			3'd4: if (sqDone) begin magVal <= sqRoot; magDone <= 1'b1; ms <= 3'd0; end
			default: ms <= 3'd0;
		endcase
	end

	// ---------------------------------------------------------------- divider for interpolation
	reg         dvStart;
	reg  [31:0] dvNum;
	reg  [19:0] dvDen;
	wire        dvDone;
	wire [31:0] dvQuot;
	DivSeq #(.NW(32), .DW(20)) dv0 (.clk(clk), .reset(reset), .start(dvStart), .num(dvNum), .den(dvDen), .done(dvDone), .quot(dvQuot));

	// ---------------------------------------------------------------- main FSM
	localparam S_IDLE = 5'd0, S_H1 = 5'd1, S_H1W = 5'd2, S_H2 = 5'd3, S_H2W = 5'd4, S_HMUL = 5'd5, S_HCMP = 5'd6,
	           S_P = 5'd7, S_PW = 5'd8, S_PNEXT = 5'd9, S_SEL = 5'd10, S_INT = 5'd11, S_INTW = 5'd12, S_FIN = 5'd13,
	           S_H3 = 5'd14, S_H3W = 5'd15, S_HMUL2 = 5'd16;

	reg [4:0]  st;
	reg [10:0] k;
	reg [17:0] m1, m2, m3;
	reg [35:0] p12;
	reg [38:0] score, best;
	reg [10:0] bestK;
	reg [17:0] pm0, pm1, pm2, pm3, pm4, pm5, pm6;
	reg [2:0]  pcnt;
	reg [10:0] kp;
	reg [17:0] mc, mn;
	reg        up;
	reg [17:0] t_mx;
	reg [2:0]  t_i;
	reg [17:0] t_l, t_r;

	always @(posedge clk)
	begin
		done <= 1'b0;
		magReq <= 1'b0;
		dvStart <= 1'b0;

		if (reset) st <= S_IDLE;
		else case (st)
			S_IDLE: if (go) begin k <= kLo; best <= 39'd0; bestK <= kLo; st <= S_H1; end

			// ---- harmonic product scan
			S_H1:  begin magAddr <= k;          magReq <= 1'b1; st <= S_H1W; end
			S_H1W: if (magDone) begin m1 <= magVal; st <= S_H2; end
			S_H2:  begin magAddr <= {k[9:0], 1'b0}; magReq <= 1'b1; st <= S_H2W; end
			S_H2W: if (magDone) begin m2 <= magVal; st <= S_H3; end
			S_H3:  begin
				if (k > 11'd682) begin m3 <= m2; st <= S_HMUL; end            // 3k would exceed bin 2047
				else begin magAddr <= k + {k[9:0], 1'b0}; magReq <= 1'b1; st <= S_H3W; end
			end
			S_H3W: if (magDone) begin m3 <= magVal; st <= S_HMUL; end
			// +m1/32 keeps a pure sine (no harmonics) detectable; p12 is scaled down so the 2nd multiply stays small
			S_HMUL:  begin p12 <= m1 * (m2 + (m1 >> 5)); st <= S_HMUL2; end
			S_HMUL2: begin score <= p12[35:14] * (m3 + (m1 >> 5)); st <= S_HCMP; end
			S_HCMP: begin
				if (score > best) begin best <= score; bestK <= k; end
				if (k == {1'b0, kHi}) begin pcnt <= 3'd0; st <= S_P; end
				else begin k <= k + 1'b1; st <= S_H1; end
			end

			// ---- read 7 magnitudes bestK-3 .. bestK+3
			S_P:  begin magAddr <= bestK - 11'd3 + pcnt; magReq <= 1'b1; st <= S_PW; end
			S_PW: if (magDone) begin
				pm0 <= pm1; pm1 <= pm2; pm2 <= pm3; pm3 <= pm4; pm4 <= pm5; pm5 <= pm6; pm6 <= magVal;
				st <= S_PNEXT;
			end
			S_PNEXT: begin
				if (pcnt == 3'd6) st <= S_SEL;
				else begin pcnt <= pcnt + 1'b1; st <= S_P; end
			end

			// ---- choose the largest of pm1..pm5 (first one wins ties)
			S_SEL: begin
				t_mx = pm1; t_i = 3'd1;
				if (pm2 > t_mx) begin t_mx = pm2; t_i = 3'd2; end
				if (pm3 > t_mx) begin t_mx = pm3; t_i = 3'd3; end
				if (pm4 > t_mx) begin t_mx = pm4; t_i = 3'd4; end
				if (pm5 > t_mx) begin t_mx = pm5; t_i = 3'd5; end
				case (t_i)
					3'd1: begin t_l = pm0; t_r = pm2; end
					3'd2: begin t_l = pm1; t_r = pm3; end
					3'd3: begin t_l = pm2; t_r = pm4; end
					3'd4: begin t_l = pm3; t_r = pm5; end
					default: begin t_l = pm4; t_r = pm6; end
				endcase
				kp <= bestK - 11'd3 + t_i;
				mc <= t_mx;
				up <= (t_r >= t_l);
				mn <= (t_r >= t_l) ? t_r : t_l;
				st <= S_INT;
			end

			// ---- Hann ratio interpolation: d256 = (2*mn - mc) * 256 / (mc + mn)
			S_INT: begin
				if (mc == 18'd0) begin found <= 1'b0; pos <= {kp, 8'd0}; st <= S_FIN; end
				else begin
					dvNum   <= (({1'b0, mn, 1'b0} > {1'b0, mc}) ? ({1'b0, mn, 1'b0} - {1'b0, mc}) : 19'd0) << 8;
					dvDen   <= mc + mn;
					dvStart <= 1'b1;
					st <= S_INTW;
				end
			end
			S_INTW: if (dvDone) begin
				found <= 1'b1;
				pos <= {kp, 8'd0} + (up ? (dvQuot[8:0] > 9'd128 ? 9'd128 : dvQuot[8:0])
				                        : -(dvQuot[8:0] > 9'd128 ? 9'd128 : dvQuot[8:0]));
				st <= S_FIN;
			end

			S_FIN: begin done <= 1'b1; st <= S_IDLE; end
			default: st <= S_IDLE;
		endcase
	end
endmodule
