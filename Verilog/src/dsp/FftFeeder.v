// Circular sample buffer + Hann window + continuous 4096-point frame feeder for the FFT MegaCore.
// A new frame (the latest 4096 decimated samples, oldest first) is streamed every 4096 clocks, back to back,
// exactly like the original FFTVisualizer fed the core (sink_valid permanently high).
// New samples are inserted only on frame boundaries so a frame is never torn.
module FftFeeder
(
	input clk,
	input reset,
	input newSample,                       // strobe: one decimated sample (interval must be > 4096 clocks)
	input signed [15:0] sample,
	output reg signed [15:0] sinkReal,     // windowed sample
	output reg sinkValid,
	output reg sinkSop,
	output reg sinkEop,
	output reg [15:0] frameLevel           // peak |x| (un-windowed) of the most recent complete frame
);
	reg signed [15:0] ram [0:4095];
	reg [15:0] hann [0:4095];
	reg [11:0] wp;                         // write pointer == index of the oldest sample
	reg [11:0] i;                          // position inside the frame
	reg pending;
	reg signed [15:0] pendData;
	reg started;

	integer j;
	initial
	begin
		for (j = 0; j < 4096; j = j + 1) ram[j] = 16'sd0;
		$readmemh("hann4096.hex", hann);
	end

	// stage 0 -> 1: memory reads
	reg signed [15:0] rd;
	reg [15:0] hw;
	reg [11:0] i1;
	wire [11:0] raddr = wp + i;
	always @(posedge clk)
	begin
		rd <= ram[raddr];
		hw <= hann[i];
		i1 <= i;
	end

	// stage 1 -> 2: window multiply (signed 16 x unsigned 16)
	reg signed [32:0] prod;
	reg s2sop, s2eop, s2v;
	always @(posedge clk)
	begin
		prod <= rd * $signed({1'b0, hw});
		s2sop <= (i1 == 12'd0);
		s2eop <= (i1 == 12'd4095);
		s2v   <= started;
	end

	// stage 2 -> 3: output register
	always @(posedge clk)
	begin
		sinkReal  <= prod[31:16];
		sinkSop   <= s2sop & s2v;
		sinkEop   <= s2eop & s2v;
		sinkValid <= s2v;
	end

	// peak level tracking on the un-windowed samples (stage 1)
	wire [15:0] absRd = rd[15] ? (~rd + 1'b1) : rd;
	reg [15:0] curMax;
	always @(posedge clk)
	begin
		if (i1 == 12'd0) curMax <= absRd;
		else if (absRd > curMax) curMax <= absRd;
		if (i1 == 12'd4095) frameLevel <= (absRd > curMax) ? absRd : curMax;
	end

	// frame counter, sample insertion
	always @(posedge clk)
	begin
		if (reset)
		begin
			i <= 12'd0; wp <= 12'd0; pending <= 1'b0; pendData <= 16'sd0; started <= 1'b0;
		end
		else
		begin
			started <= 1'b1;
			i <= i + 1'b1;
			if (i == 12'd4095 && pending)
			begin
				ram[wp] <= pendData;
				wp <= wp + 1'b1;
				pending <= 1'b0;
			end
			if (newSample)
			begin
				pending  <= 1'b1;
				pendData <= sample;
			end
		end
	end
endmodule
