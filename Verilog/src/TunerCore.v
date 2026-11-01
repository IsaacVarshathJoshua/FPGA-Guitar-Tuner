// Complete DSP + pitch chain:  samples -> CIC/16 -> window -> FFT4096 -> spectrum RAM -> HPS pitch -> note/cents
module TunerCore #(parameter BIT_REVERSED = 0, parameter PAUSE_CLKS = 2000000)   // 40 ms between measurements
(
	input clk,
	input reset,
	input sampleStrobe,                   // 1-clk strobe at the audio sample rate (48.828 kHz)
	input signed [15:0] sampleIn,
	input [1:0] sens,                     // input-level threshold: 00 = most sensitive
	input stringMode,                     // 1: guitar-string targets, 0: chromatic
	input fs32,                           // 1: codec really runs at 32.552 kHz (LRCLK = 1536 clocks), 0: 48.828 kHz (1024 clocks)

	output reg signalValid,               // a pitch is being displayed (held for ~1 s after the signal vanishes)
	output reg [6:0] midi,
	output reg signed [14:0] cents16,
	output reg [2:0] stringIdx,
	output reg [13:0] hz10,               // frequency in 0.1 Hz
	output reg tick                       // toggles after every processed frame
);
	// ------------------------------------------------------------ front end
	wire cicValid;
	wire signed [15:0] cicData;
	CicDecimator #(.IN_W(16), .R_LOG2(4)) cic0
		(.clk(clk), .reset(reset), .inValid(sampleStrobe), .inData(sampleIn), .outValid(cicValid), .outData(cicData));

	wire signed [15:0] sinkReal;
	wire sinkValid, sinkSop, sinkEop;
	wire [15:0] frameLevel;
	FftFeeder fed0
		(.clk(clk), .reset(reset), .newSample(cicValid), .sample(cicData),
		 .sinkReal(sinkReal), .sinkValid(sinkValid), .sinkSop(sinkSop), .sinkEop(sinkEop), .frameLevel(frameLevel));

	wire srcValid, srcSop, srcEop;
	wire [15:0] srcRe, srcIm;
	FFT_mf fft0
	(
		.clk(clk), .reset_n(~reset), .inverse(1'b0),
		.sink_valid(sinkValid), .sink_sop(sinkSop), .sink_eop(sinkEop),
		.sink_real(sinkReal), .sink_imag(16'd0), .sink_error(2'b00),
		.source_ready(1'b1),
		.sink_ready(), .source_error(),
		.source_sop(srcSop), .source_eop(srcEop), .source_valid(srcValid),
		.source_exp(), .source_real(srcRe), .source_imag(srcIm)
	);

	// ------------------------------------------------------------ spectrum + pitch
	reg arm;
	wire capDone;
	wire [10:0] rdAddr;
	wire [15:0] rdRe, rdIm;
	SpectrumCapture #(.BIT_REVERSED(BIT_REVERSED)) cap0
		(.clk(clk), .reset(reset), .arm(arm), .srcValid(srcValid), .srcSop(srcSop), .srcEop(srcEop),
		 .srcRe(srcRe), .srcIm(srcIm), .done(capDone), .rdAddr(rdAddr), .rdRe(rdRe), .rdIm(rdIm));

	reg detGo;
	wire detDone, detFound;
	wire [17:0] detPos;
	PitchDetector det0
		(.clk(clk), .reset(reset), .go(detGo), .kLo(fs32 ? 11'd120 : 11'd80), .kHi(fs32 ? 10'd960 : 10'd640), .rdAddr(rdAddr), .rdRe(rdRe), .rdIm(rdIm),
		 .done(detDone), .found(detFound), .pos(detPos));

	reg mapGo;
	reg [17:0] posF;
	// posF is in 'design' units (assumes Fs = 48828 Hz). With a 32.552 kHz codec the true frequency is exactly 2/3 of it.
	wire [33:0] posScaled = posF * 16'd43691;                    // x 2/3 (43691/65536)
	wire [17:0] posT = fs32 ? posScaled[33:16] : posF;
	wire mapDone;
	wire [6:0] mapMidi;
	wire signed [14:0] mapCents;
	wire [2:0] mapStr;
	NoteMapper map0
		(.clk(clk), .reset(reset), .go(mapGo), .pos(posT), .stringMode(stringMode),
		 .done(mapDone), .midi(mapMidi), .cents16(mapCents), .stringIdx(mapStr));

	// ------------------------------------------------------------ control
	localparam S_ARM = 3'd0, S_WCAP = 3'd1, S_WDET = 3'd2, S_WMAP = 3'd3, S_PAUSE = 3'd4;
	localparam HOLD_FRAMES = 6'd25;

	reg [2:0]  st;
	reg [15:0] lvl;
	reg [21:0] pcnt;
	reg [5:0]  holdCnt;
	reg        havePrev;

	reg [15:0] thr;
	always @* case (sens) 2'd0: thr = 16'd80; 2'd1: thr = 16'd160; 2'd2: thr = 16'd320; default: thr = 16'd640; endcase

	wire [17:0] dPos = (detPos > posF) ? (detPos - posF) : (posF - detPos);
	// posF is in 'design' units (assumes Fs = 48828 Hz). With a 32.552 kHz codec the true frequency is exactly 2/3 of it.
	wire [31:0] hzMul = posT * 14'd7630;          // pos * 0.0291061 = Hz*10   (unit = 0.002910383 Hz)

	always @(posedge clk)
	begin
		arm <= 1'b0; detGo <= 1'b0; mapGo <= 1'b0;
		if (reset)
		begin
			st <= S_ARM; signalValid <= 1'b0; holdCnt <= 6'd0; havePrev <= 1'b0; tick <= 1'b0;
			midi <= 7'd0; cents16 <= 15'sd0; stringIdx <= 3'd7; hz10 <= 14'd0; posF <= 18'd0; pcnt <= 22'd0; lvl <= 16'd0;
		end
		else case (st)
			S_ARM: begin arm <= 1'b1; st <= S_WCAP; end

			S_WCAP: if (capDone) begin lvl <= frameLevel; detGo <= 1'b1; st <= S_WDET; end

			S_WDET: if (detDone) begin
				if (detFound && lvl >= thr)
				begin
					// light smoothing: follow small changes at 1/2 rate, jump on large changes (new string / first frame)
					if (!havePrev || dPos > 18'd2048) posF <= detPos;
					else posF <= (detPos > posF) ? (posF + (dPos >> 1)) : (posF - (dPos >> 1));
					havePrev <= 1'b1;
					mapGo <= 1'b1;
					st <= S_WMAP;
				end
				else
				begin
					havePrev <= 1'b0;
					if (holdCnt == 6'd0) signalValid <= 1'b0; else holdCnt <= holdCnt - 1'b1;
					tick <= ~tick;
					pcnt <= 22'd0; st <= S_PAUSE;
				end
			end

			S_WMAP: if (mapDone) begin
				midi <= mapMidi; cents16 <= mapCents; stringIdx <= mapStr;
				hz10 <= hzMul[31:18];
				signalValid <= 1'b1; holdCnt <= HOLD_FRAMES;
				tick <= ~tick;
				pcnt <= 22'd0; st <= S_PAUSE;
			end

			S_PAUSE: begin
				pcnt <= pcnt + 1'b1;
				if (pcnt == PAUSE_CLKS) st <= S_ARM;
			end
			default: st <= S_ARM;
		endcase
	end
endmodule