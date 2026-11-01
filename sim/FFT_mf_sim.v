// Behavioural stand-in for the Altera FFT_mf megacore (streaming, 4096 pt, natural order in/out), SIMULATION ONLY.
// - collects a frame on sink_*, computes a double-precision FFT, quantises to 16 bit with a block exponent,
// - streams the frame out 4096 clocks later, back-to-back like the real core.
// calc_en lets the testbench skip the (slow) FFT while the sample buffer is still filling.
module FFT_mf
(
	input clk, input reset_n, input inverse,
	input sink_valid, input sink_sop, input sink_eop,
	input [15:0] sink_real, input [15:0] sink_imag, input [1:0] sink_error,
	input source_ready,
	output sink_ready, output [1:0] source_error,
	output reg source_sop, output reg source_eop, output reg source_valid,
	output reg [5:0] source_exp, output reg [15:0] source_real, output reg [15:0] source_imag
);
	parameter N = 4096;
	reg calc_en;
	initial calc_en = 1'b1;
	assign sink_ready = 1'b1;
	assign source_error = 2'b00;

	real xr [0:N-1]; real xi [0:N-1];
	reg signed [15:0] ore [0:1][0:N-1]; reg signed [15:0] oim [0:1][0:N-1];
	reg signed [5:0] oexp [0:1];
	integer ic, oc, wbuf, rbuf, pend, startDelay;
	reg outActive;

	task do_fft;
		input integer buf_sel;
		integer i, j, k, m, len, half, s;
		real wr, wi, tr, ti, ang, mx, sc;
		real ar [0:N-1]; real ai [0:N-1];
		begin
			// bit-reversal copy
			for (i = 0; i < N; i = i + 1) begin
				j = 0; k = i;
				for (m = 0; m < 12; m = m + 1) begin j = (j << 1) | (k & 1); k = k >> 1; end
				ar[j] = xr[i]; ai[j] = xi[i];
			end
			len = 2;
			while (len <= N) begin
				half = len / 2;
				for (i = 0; i < N; i = i + len)
					for (k = 0; k < half; k = k + 1) begin
						ang = -6.283185307179586 * k / len;
						wr = $cos(ang); wi = $sin(ang);
						tr = ar[i+k+half]*wr - ai[i+k+half]*wi;
						ti = ar[i+k+half]*wi + ai[i+k+half]*wr;
						ar[i+k+half] = ar[i+k] - tr; ai[i+k+half] = ai[i+k] - ti;
						ar[i+k] = ar[i+k] + tr;      ai[i+k] = ai[i+k] + ti;
					end
				len = len * 2;
			end
			mx = 1.0;
			for (i = 0; i < N; i = i + 1) begin
				if (ar[i] > mx) mx = ar[i]; if (-ar[i] > mx) mx = -ar[i];
				if (ai[i] > mx) mx = ai[i]; if (-ai[i] > mx) mx = -ai[i];
			end
			s = 0; sc = 1.0;
			while (mx / sc > 32767.0) begin sc = sc * 2.0; s = s + 1; end
			for (i = 0; i < N; i = i + 1) begin
				ore[buf_sel][i] = $rtoi($floor(ar[i]/sc + 0.5));
				oim[buf_sel][i] = $rtoi($floor(ai[i]/sc + 0.5));
			end
			oexp[buf_sel] = -s;
		end
	endtask

	integer q;
	always @(posedge clk) begin
		if (!reset_n) begin
			ic <= 0; oc <= 0; wbuf = 0; rbuf = 0; pend = 0; outActive <= 0; startDelay = 0;
			source_valid <= 0; source_sop <= 0; source_eop <= 0;
		end else begin
			source_valid <= 0; source_sop <= 0; source_eop <= 0;
			// ---- input side
			if (sink_valid) begin
				xr[ic] = $signed(sink_real); xi[ic] = $signed(sink_imag);
				if (sink_eop) begin
					if (calc_en) do_fft(wbuf);
					else begin for (q = 0; q < N; q = q + 1) begin ore[wbuf][q] = 0; oim[wbuf][q] = 0; end oexp[wbuf] = 0; end
					pend = pend + 1; wbuf = 1 - wbuf; ic <= 0;
					if (!outActive && startDelay == 0) startDelay = 20;      // latency before output starts
				end else ic <= ic + 1;
			end
			// ---- output side
			if (startDelay > 0) begin
				startDelay = startDelay - 1;
				if (startDelay == 0) begin outActive <= 1; oc <= 0; end
			end
			if (outActive) begin
				source_valid <= 1; source_sop <= (oc == 0); source_eop <= (oc == N-1);
				source_real <= ore[rbuf][oc]; source_imag <= oim[rbuf][oc]; source_exp <= oexp[rbuf];
				if (oc == N-1) begin
					oc <= 0; pend = pend - 1; rbuf = 1 - rbuf;
					if (pend == 0) outActive <= 0;
				end else oc <= oc + 1;
			end
		end
	end
endmodule
