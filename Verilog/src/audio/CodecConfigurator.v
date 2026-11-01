/*
*
* Copyright (c) 2015 Goshik (goshik92@gmail.com)
*
*
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
* 
*/

module CodecConfigurator
(
	input reset,
	input inClock,
	input micMode,   // 1: MIC input, 0: LINE-IN (sampled whenever the codec is (re)configured, i.e. after reset)
	input micBoost,  // 1: +20 dB mic boost (only used in mic mode)
	inout sda,
	inout scl,
	output reg ready,
	output reg [3:0] ackNum
);

	localparam DEVICE_ADDR = 8'h34;

	reg i2cClockDisable;
	reg [23:0] data;
	reg [2:0] state;
	wire txReady, ack;
	
	I2CMaster i2cm1
	(
		.reset(reset),
		.inClock(i2cClockDisable ? 1'b0 : inClock),
		.inData(data),
		.sda(sda),
		.scl(scl),
		.ready(txReady),
		.ack(ack)
	);

	always @(posedge txReady or posedge reset)
	begin
		if (reset)
		begin
			i2cClockDisable <= 1'b0;
			state <= 1'b0;
			ready <= 1'b0;
			data <= 8'h00;
			ackNum <= 1'b0;
		end
	
		else
		begin
			case(state)	
				// Send Analogue Audio Path Control register
				3'h0: data <= {DEVICE_ADDR, 7'h04, 6'b0_0000_0, micMode, 1'b0, (micMode & micBoost)};  // INSEL, MUTEMIC=0, MICBOOST
				
				// Send Digital Audio Interface Format register
				3'h1: data <= {DEVICE_ADDR, 7'h07, 9'b0_0100_0010};
				
				// Send Active Control register
				3'h2: data <= {DEVICE_ADDR, 7'h09, 9'b0_0000_0001};
				
				// Send Power Down Control register
				3'h3: data <= {DEVICE_ADDR, 7'h06, 7'b000_1110, (micMode ? 2'b01 : 2'b10)};  // OSC/OUT/DAC off; mic mode: MICPD=0,LINEINPD=1; line mode: MICPD=1,LINEINPD=0
				
				// Send Left Line In register
				3'h4: data <= {DEVICE_ADDR, 7'h00, 9'b0_0001_0111};
				
				// Send Right Line In register
				3'h5: data <= {DEVICE_ADDR, 7'h01, 9'b0_0001_0111};

				// Sampling Control register: normal mode, BOSR=0 (256fs), SR=0000  ->  Fs = 12.5 MHz / 256 = 48828 Hz
				// (the codec keeps old register values after a FPGA reload, so set it explicitly)
				3'h6: data <= {DEVICE_ADDR, 7'h08, 9'b0_0000_0000};
			endcase
			
			if (state == 3'h7)
			begin
				ready <= 1'b1;
				i2cClockDisable <= 1'b1;
			end
			
			else state <= state + 1'b1;
			ackNum <= ackNum + ack; 
		end
	end

endmodule
