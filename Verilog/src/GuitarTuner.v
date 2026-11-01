// FPGA guitar tuner for the Terasic DE2-115 (Quartus II 13.0)
//
//  Controls
//    KEY[0]   reset (also re-configures the audio codec)
//    SW[17]   audio input: 1 = MIC jack (pink), 0 = LINE-IN jack (blue)   -- read when the codec is configured (after reset)
//    SW[16]   codec channel: 1 = left, 0 = right  (as in the original FFTVisualizer)
//    SW[15:14] input threshold: 00 most sensitive ... 11 least sensitive
//    SW[13]   (unused) the tuner is always in guitar-string mode: it shows only E A D G B E (the nearest string) and the cents to tune
//    SW[12]   HEX display: 0 = note + cents, 1 = frequency in 0.1 Hz
//    SW[11]   mic boost +20 dB (mic mode only)
//  Outputs: VGA tuner screen, HEX7..0, LEDR meter (red = flat on the left, sharp on the right), LEDG in-tune lamp
module GuitarTuner
(
	input CLOCK_50,
	input AUD_ADCDAT,
	input AUD_ADCLRCK,
	input AUD_BCLK,
	output AUD_XCK,
	inout I2C_SCLK,
	inout I2C_SDAT,
	input [3:0] KEY,
	input [17:0] SW,
	output [8:0] LEDG,
	output [17:0] LEDR,
	output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B,
	output VGA_BLANK_N,
	output VGA_SYNC_N,
	output VGA_CLK,
	output VGA_HS,
	output VGA_VS
);
	// ------------------------------------------------------------------ clocks / reset / codec (unchanged from FFTVisualizer)
	wire i2cClock, codecClock, configReady;
	wire reset = ~KEY[0];
	assign AUD_XCK = codecClock;
	ClockDivider #(.DIVIDER(500)) cd0 (.reset(reset), .inClock(CLOCK_50), .outClock(i2cClock));
	ClockDivider #(.DIVIDER(4))   cd1 (.reset(reset), .inClock(CLOCK_50), .outClock(codecClock));   // 12.5 MHz -> Fs = 48828.125 Hz

	CodecConfigurator cc0 (.reset(reset), .inClock(i2cClock), .micMode(SW[17]), .micBoost(SW[11]),
	                       .sda(I2C_SDAT), .scl(I2C_SCLK), .ready(configReady));

	wire coreReset = reset | ~configReady;

	wire signed [15:0] leftData, rightData;
	wire dataReady;
	I2SReceiver #(.WORD_SIZE(16)) i2sr0
	(
		.reset(~configReady), .codecBitClock(AUD_BCLK), .codecLRClock(AUD_ADCLRCK), .codecData(AUD_ADCDAT),
		.dataReady(dataReady), .outDataLeft(leftData), .outDataRight(rightData)
	);

	// BCLK -> CLOCK_50 crossing: the sample registers are stable for ~half a frame after dataReady rises
	reg [2:0] drSync;
	reg signed [15:0] audio;
	reg audioStrobe;
	always @(posedge CLOCK_50)
	begin
		drSync <= {drSync[1:0], dataReady};
		audioStrobe <= drSync[1] & ~drSync[2];
		if (drSync[1] & ~drSync[2]) audio <= SW[16] ? leftData : rightData;
	end

	// Measure the real codec sample rate: CLOCK_50 clocks per audio frame = 1024 (48.828 kHz) or 1536 (32.552 kHz)
	reg [10:0] frmClks;
	reg        fs32;
	always @(posedge CLOCK_50)
	begin
		if (reset) begin frmClks <= 11'd0; fs32 <= 1'b0; end
		else if (audioStrobe) begin fs32 <= (frmClks > 11'd1280); frmClks <= 11'd1; end
		else if (frmClks != 11'd2047) frmClks <= frmClks + 1'b1;
	end

	// ------------------------------------------------------------------ DSP + pitch
	wire tValid, tTick;
	wire [6:0] tMidi;
	wire signed [14:0] tCents;
	wire [2:0] tStr;
	wire [13:0] tHz10;
	TunerCore core0
	(
		.clk(CLOCK_50), .reset(coreReset), .sampleStrobe(audioStrobe), .sampleIn(audio),
		.sens(SW[15:14]), .stringMode(1'b1), .fs32(fs32),
		.signalValid(tValid), .midi(tMidi), .cents16(tCents), .stringIdx(tStr), .hz10(tHz10), .tick(tTick)
	);

	// ------------------------------------------------------------------ display values
	reg tickD;
	reg bcdStart;
	always @(posedge CLOCK_50) begin tickD <= tTick; bcdStart <= (tTick != tickD); end

	// MIDI -> note name / octave
	reg [3:0] nIdx, oct;
	reg [3:0] q;
	reg [6:0] r;
	integer ii;
	always @*
	begin
		r = tMidi; q = 4'd0;
		for (ii = 0; ii < 7; ii = ii + 1) if (r >= 7'd12) begin r = r - 7'd12; q = q + 4'd1; end
		nIdx = r[3:0];
		oct  = q - 4'd1;
	end
	reg [4:0] letter;      // 10..16 = A b C d E F G
	reg       sharp;
	always @*
		case (nIdx)
			4'd0:  begin letter = 5'd12; sharp = 1'b0; end   // C
			4'd1:  begin letter = 5'd12; sharp = 1'b1; end   // C#
			4'd2:  begin letter = 5'd13; sharp = 1'b0; end   // d
			4'd3:  begin letter = 5'd13; sharp = 1'b1; end   // d#
			4'd4:  begin letter = 5'd14; sharp = 1'b0; end   // E
			4'd5:  begin letter = 5'd15; sharp = 1'b0; end   // F
			4'd6:  begin letter = 5'd15; sharp = 1'b1; end   // F#
			4'd7:  begin letter = 5'd16; sharp = 1'b0; end   // G
			4'd8:  begin letter = 5'd16; sharp = 1'b1; end   // G#
			4'd9:  begin letter = 5'd10; sharp = 1'b0; end   // A
			4'd10: begin letter = 5'd10; sharp = 1'b1; end   // A#
			default: begin letter = 5'd11; sharp = 1'b0; end // b (B)
		endcase

	// cents: dead band of +-5 cents shows 0 (= "no correction"); otherwise up to 999 cents, 3 digits
	wire [14:0] cRaw16 = tCents[14] ? -tCents : tCents;
	wire        cZero  = (cRaw16 <= 15'd80);
	wire [14:0] cAbs16 = cZero ? 15'd0 : cRaw16;
	wire        cNeg   = tCents[14] & ~cZero;
	wire [9:0]  cAbsInt = (cAbs16 + 15'd8) >> 4;                 // rounded, 0..999
	wire [7:0]  cVga   = (cAbsInt > 10'd50) ? 8'd50 : cAbsInt[7:0];    // VGA gauge only spans +-50
	wire signed [7:0] cInt = cNeg ? -$signed(cVga) : $signed(cVga);

	wire [15:0] hzBcd;
	wire [11:0] cBcd;
	wire hzDone, cDone;
	Bin2Bcd #(.W(14), .D(4)) b2b0 (.clk(CLOCK_50), .reset(reset), .start(bcdStart), .bin(tHz10), .done(hzDone), .bcd(hzBcd));
	Bin2Bcd #(.W(14), .D(3)) b2b1 (.clk(CLOCK_50), .reset(reset), .start(bcdStart), .bin({4'd0, cAbsInt}), .done(cDone), .bcd(cBcd));

	// ------------------------------------------------------------------ 7-segment displays
	reg [4:0] h7, h6, h5, h4, h3, h2, h1, h0;
	always @*
	begin
		{h7, h6, h5, h4, h3, h2, h1, h0} = {8{5'd18}};
		if (!tValid) {h7, h6, h5, h4, h3, h2, h1, h0} = {8{5'd17}};                // ---- = no signal
		else if (!SW[12])
		begin
			h7 = letter; h6 = sharp ? 5'd19 : 5'd18; h5 = {1'b0, oct};
			h3 = cNeg ? 5'd17 : 5'd18;                                   // '-' = tune UP (note is flat), blank = tune DOWN (sharp)
			h2 = (cBcd[11:8] != 4'd0) ? {1'b0, cBcd[11:8]} : 5'd18;
			h1 = {1'b0, cBcd[7:4]}; h0 = {1'b0, cBcd[3:0]};
		end
		else
		begin
			h3 = (hzBcd[15:12] != 4'd0) ? {1'b0, hzBcd[15:12]} : 5'd18;
			h2 = (hzBcd[15:12] != 4'd0 || hzBcd[11:8] != 4'd0) ? {1'b0, hzBcd[11:8]} : 5'd18;
			h1 = {1'b0, hzBcd[7:4]}; h0 = {1'b0, hzBcd[3:0]};
		end
	end
	Seg7 s7 (.code(h7), .seg(HEX7)); Seg7 s6 (.code(h6), .seg(HEX6)); Seg7 s5 (.code(h5), .seg(HEX5)); Seg7 s4 (.code(h4), .seg(HEX4));
	Seg7 s3 (.code(h3), .seg(HEX3)); Seg7 s2 (.code(h2), .seg(HEX2)); Seg7 s1 (.code(h1), .seg(HEX1)); Seg7 s0 (.code(h0), .seg(HEX0));

	// ------------------------------------------------------------------ LED meter: 5 cents per LED, in-tune window +-5 cents
	reg [3:0] nLed;
	always @*
		nLed = (cAbs16 > 15'd80) + (cAbs16 > 12'd160) + (cAbs16 > 12'd240) + (cAbs16 > 12'd320) + (cAbs16 > 12'd400) +
		       (cAbs16 > 12'd480) + (cAbs16 > 12'd560) + (cAbs16 > 12'd640) + (cAbs16 > 12'd720);
	reg [8:0] therm, thermRev;
	integer jj;
	always @*
	begin
		therm = 9'd0;
		for (jj = 0; jj < 9; jj = jj + 1) if (jj < nLed) therm[jj] = 1'b1;
		for (jj = 0; jj < 9; jj = jj + 1) thermRev[jj] = therm[8-jj];
	end
	wire inTune = tValid && cZero;
	assign LEDR = !tValid ? 18'd0 : {cNeg ? therm : 9'd0, cNeg ? 9'd0 : thermRev};
	assign LEDG = {tTick, {7{inTune}}, inTune};      // LEDG[8] = heartbeat (toggles each measurement)

	// ------------------------------------------------------------------ VGA
	wire pixelClock;
	VGAClockSource vgacs0 (.areset(reset), .inclk0(CLOCK_50), .c0(pixelClock));
	assign VGA_CLK = pixelClock;
	assign VGA_SYNC_N = 1'b0;
	TunerRaster ras0
	(
		.pixClk(pixelClock), .reset(reset),
		.dValid(tValid), .dLetter(letter), .dSharp(sharp), .dOctave(oct), .dCents(cInt), .dString(tStr), .dBcd(hzBcd),
		.hSync(VGA_HS), .vSync(VGA_VS), .blankN(VGA_BLANK_N), .rOut(VGA_R), .gOut(VGA_G), .bOut(VGA_B)
	);
endmodule
