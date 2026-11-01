// Maps pos (1/256-bin units) to the nearest note (chromatic) or the nearest guitar string and computes the deviation:
//   cents = 1200*log2(f/fn)  ~=  3462.468 * (f-fn)/(f+fn)     (error < 0.001 cent for |dev| < 100 cents)
// cents16 = cents * 16  (signed 15 bit, clamped to +-15984 = +-999 cents)
module NoteMapper
(
	input clk,
	input reset,
	input go,
	input [17:0] pos,
	input stringMode,                     // 1: nearest of the six guitar strings, 0: nearest semitone
	output reg done,                      // 1-clk pulse
	output reg [6:0] midi,                // MIDI number of the target note
	output reg signed [14:0] cents16,
	output reg [2:0] stringIdx            // 0..5 = E A D G B E, 7 = none
);
	reg [5:0] idx;
	wire [17:0] nFreq, nBound, sFreq, sBound;
	wire [6:0]  nMidi, sMidi;
	NoteRom   nr (.idx(idx), .freq(nFreq), .bound(nBound), .midi(nMidi));
	StringRom sr (.idx(idx), .freq(sFreq), .bound(sBound), .midi(sMidi));

	wire [17:0] fT = stringMode ? sFreq  : nFreq;
	wire [17:0] bT = stringMode ? sBound : nBound;
	wire [6:0]  mT = stringMode ? sMidi  : nMidi;
	wire [5:0]  idxMax = stringMode ? 6'd5 : 6'd36;

	reg [17:0] fn;
	reg        neg;
	reg [17:0] absDiff;
	reg [33:0] dvNum;
	reg        dvStart;
	wire       dvDone;
	wire [33:0] dvQuot;
	DivSeq #(.NW(34), .DW(20)) dv1
	(
		.clk(clk), .reset(reset), .start(dvStart), .num(dvNum),
		.den({1'b0, pos} + {1'b0, fn}), .done(dvDone), .quot(dvQuot)
	);

	function [2:0] strOf(input [6:0] m);
		case (m)
			7'd40: strOf = 3'd0;  7'd45: strOf = 3'd1;  7'd50: strOf = 3'd2;
			7'd55: strOf = 3'd3;  7'd59: strOf = 3'd4;  7'd64: strOf = 3'd5;
			default: strOf = 3'd7;
		endcase
	endfunction

	localparam S_IDLE = 3'd0, S_SCAN = 3'd1, S_DIFF = 3'd2, S_MUL = 3'd3, S_DIV = 3'd4, S_FIN = 3'd5;
	reg [2:0] st;
	wire [14:0] clampQ = (dvQuot > 34'd15984) ? 15'd15984 : dvQuot[14:0];

	always @(posedge clk)
	begin
		done <= 1'b0;
		dvStart <= 1'b0;
		if (reset) st <= S_IDLE;
		else case (st)
			S_IDLE: if (go) begin idx <= 6'd0; st <= S_SCAN; end

			S_SCAN:   // walk up the table until pos is below the upper boundary of entry idx
				if (pos < bT || idx == idxMax) begin
					fn <= fT; midi <= mT; stringIdx <= strOf(mT);
					st <= S_DIFF;
				end
				else idx <= idx + 1'b1;

			S_DIFF: begin
				neg     <= (pos < fn);
				absDiff <= (pos < fn) ? (fn - pos) : (pos - fn);
				st <= S_MUL;
			end

			S_MUL: begin dvNum <= absDiff * 16'd55400; dvStart <= 1'b1; st <= S_DIV; end  // 3462.468*16 = 55399.5

			S_DIV: if (dvDone) begin
				cents16 <= neg ? -$signed(clampQ) : $signed(clampQ);
				st <= S_FIN;
			end

			S_FIN: begin done <= 1'b1; st <= S_IDLE; end
			default: st <= S_IDLE;
		endcase
	end
endmodule
