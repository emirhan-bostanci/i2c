`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09.05.2023 16:56:46
// Design Name:
// Module Name: ADT7420
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module ADT7420
#(
parameter clkfreq = 100_000_000,
i2c_bus_clk = 400_000,
device_addr = 7'b1001011
// input_clk = 100_000_000,
// bus_clk = 400_000

)
(
input clk_i,
input rst_n_i,
inout SCL,
inout SDA,
output reg interrupt,
output reg [12:0] temp
);
// SIGNALS
reg ena = 1'b0;
// constant addr = 7'b1100111;
reg rw = 1'b0;
reg [7:0] data_wr = 8'b0;
wire busy;
reg busyPrev = 1'b0;
wire [7:0] data_rd;
wire ack_error;
reg enable = 1'b0;
reg waitEn = 1'b0;
reg [7:0] cntr = 8'b0;
// state machine
localparam IDLE_S = 0;
localparam ACQUIRE_S = 1;
reg [1:0] state = IDLE_S;

// SIGNALS
localparam [31:0] cntr250msLim = clkfreq/4; // 4 Hz
//localparam integer cntr250msLim = clkFreq/1000; // for test
reg [31:0] cntr250 = 0;
reg cntr250msEn = 1'b1;
reg cntr250msTick = 1'b0;
reg [20:0] busyCntr = 0;
i2c_master
#(
.input_clk (25_000_000),
.bus_clk (400_000)
)
i2c_master_ad
(
.clk (clk_i),
.reset_n (rst_n_i),
.ena (ena),
.addr (device_addr),
.rw (rw),
.data_wr (data_wr),
.busy (busy),
.data_rd (data_rd),
.ack_error (ack_error),
.sda (SDA),
.scl (SCL)
);

always @(posedge clk_i) begin
case (state)
// IDLE durumunda slave'e register adres icin write command gonderiliyor
// ilk guc acilip reset kalktiginda 250 ms bekleniliyor
// bir daha bu 250 ms reset olmadikca beklenmiyor
IDLE_S: begin
busyPrev <= busy;
if (busyPrev == 1'b0 && busy == 1'b1) begin
busyCntr <= busyCntr + 1;
end
interrupt <= 1'b0;
// datasheet'te neden 250 ms beklemem gerektigi yaziyor
if (rst_n_i == 1'b1) begin
if (cntr250msTick == 1'b1) begin
enable <= 1'b1;
end
end else begin
enable <= 1'b0;
end
if (enable == 1'b1) begin
if (busyCntr == 0) begin // first byte write
ena <= 1'b1;

rw <= 1'b0; // write
data_wr <= 8'h00; // temperature MSB
end else if (busyCntr == 1) begin
ena <= 1'b0;
if (busy == 1'b0) begin
waitEn <= 1'b1;
busyCntr <= 0;
enable <= 1'b0;
end
end
end
// wait a little bit - not so critical
// bu aslinda kritik, datasheette STOP sonrasi START condition icin min bekleme zamani olarak 1.3 us denilmis
// burada beklenecek sure parametrik olsa daha iyi olur, CLKFREQ parametresi ile ifade edilmeli
if (waitEn == 1'b1) begin
if (cntr == 255) begin
state <= ACQUIRE_S;
cntr <= 8'd0;
waitEn <= 1'b0;
end else begin
cntr <= cntr + 1;
end
end
end
ACQUIRE_S: begin
busyPrev <= busy;

if (busyPrev == 1'b0 && busy == 1'b1) begin
busyCntr <= busyCntr + 1;
end
if (busyCntr == 0) begin
ena <= 1'b1;
rw <= 1'b1; // read
data_wr <= 8'h00;
end else if (busyCntr == 1) begin // read starts
if (busy == 1'b0) begin
temp[12:5] <= data_rd;
end
rw <= 1'b1;
end else if (busyCntr == 2) begin // data read
ena <= 1'b0;
if (busy == 0) begin
temp[4:0] <= data_rd[7:3];
state <= IDLE_S;
busyCntr <= 0;
interrupt <= 1'B1;
end
end
end
endcase
end
always @(posedge clk_i) begin
if (cntr250msEn == 1'b1) begin

if (cntr250 == cntr250msLim - 1) begin
cntr250msTick <= 1'b1;
cntr250 <= 0;
end else begin
cntr250msTick <= 1'b0;
cntr250 <= cntr250 + 1;
end
end else begin
cntr250msTick <= 1'b0;
cntr250 <= 0;
end
end
endmodule