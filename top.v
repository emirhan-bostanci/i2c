`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.05.2023 23:49:53
// Design Name: 
// Module Name: top
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


module top(
    
    input wire clk_i,
    input wire rst_n_i,
    output wire o_Tx_Serial,
    output wire [15:0] LED,
    inout SCL,
    inout SDA
    
    );
    ////uart_tx///
    reg i_Tx_start = 0;
    reg [7:0] i_Tx_Byte = 0;
    wire o_Tx_Active;
    wire o_Tx_Done;
    ////adt7420////
    wire interrupt;
    wire [12:0] temp;
    wire [2:0] sign;
    
    assign sign = {temp[12], temp[12], temp[12]};
    
    always @(posedge clk_i) begin
    
        i_Tx_Byte <= temp[7:0];
        
        if(interrupt) begin
        
            i_Tx_Byte <= {sign, temp[12:8]};
            i_Tx_start <= 1'b1;
        end
    
        if(o_Tx_Done) begin
        
            i_Tx_start <= 1'b0;
        
        end
    
    end
    
    assign LED [12:0]   = temp;
    assign LED [15]     = 1'b1;
    assign LED [14:13]  = 2'b00;
    
    
    adt7420
    #(
        .clkfreq     (100_000_000),
        .i2c_bus_clk (400_000),
        .device_addr (7'b1001011)
//                        input_clk   = 100_000_000,
//                        bus_clk     = 400_000
    )
    ADT7420_TT
    (
        .clk_i      (clk_i),
        .rst_n_i    (rst_n_i),
        .SCL        (SCL),
        .SDA        (SDA),
        .interrupt  (interrupt),
        .temp       (temp)
    );
    
    uart_tx_t 
    #(
        .c_clkfreq  (100_000_000),
        .c_baudrate (115_200)
    )
    uart_tx_ram
    (
        .i_clk         (clk_i),
        .i_Tx_start    (i_Tx_start),	
        .i_Tx_Byte     (i_Tx_Byte),
        .o_Tx_Active   (o_Tx_Active),		
        .o_Tx_Serial   (o_Tx_Serial),   
        .o_Tx_Done     (o_Tx_Done)
    );
    
endmodule
