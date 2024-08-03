`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.05.2023 22:50:44
// Design Name: 
// Module Name: i2c_master
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


module i2c_master
#(
parameter input_clk = 25_000_000,      //--input clock speed from user logic in Hz
parameter bus_clk   = 400_000    // --speed the i2c bus (scl) will run at in Hz

)(
input           clk         ,                //--system clock
input           reset_n     ,                // --active low reset
input           ena         ,                // --latch in command
input     [6:0] addr        ,    // --address of target slave
input           rw          ,                        // --'0' is write, '1' is read
input     [7:0] data_wr     ,          // --data to write to slave
output reg      busy        ,                     // --indicates transaction in progress
output reg[7:0] data_rd     ,        // --data read from slave
output reg      ack_error   ,     //buffer  : BUFFER STD_LOGIC;                         // --flag if improper acknowledge from slave
inout           sda         ,                // --serial data output of i2c bus
inout           scl                           // --serial clock output of i2c bus
    );
                           
reg data_clk                ;                      //--data clock for sda                        
reg data_clk_prev           ;                      //--data clock during previous system clock   
reg scl_clk                 ;                      //--constantly running internal scl           
reg scl_ena       = 0       ;                     //--enables internal scl to output            
reg sda_int       = 1       ;                      //--internal sda                              
reg sda_ena_n               ;                      //--enables internal sda to output            
reg[7:0] addr_rw            ;                     //--latched in address and read/write         
reg[7:0] data_tx            ;                       //--latched in data to write to slave         
reg[7:0] data_rx            ;                      //--data received from slave                  
reg[3:0] bit_cnt            ;                      // INTEGER RANGE 0 TO 7 := 7;      //--tracks bit number in transaction          
reg stretch      = 0        ;                       //--identifies if slave is stretching scl     


reg [31:0] count;
   // ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop
 reg [3:0] state;   
localparam ready    = 4'b0000;
localparam start    = 4'b0001;    
localparam command  = 4'b0010;
localparam slv_ack1 = 4'b0011;
localparam wr       = 4'b0100;
localparam rd       = 4'b0101;
localparam slv_ack2 = 4'b0110;
localparam mstr_ack = 4'b0111;
localparam stop     = 4'b1000;
 
localparam divider = (input_clk/bus_clk)/4;

  assign scl        = (scl_ena & ~scl_clk) ? 1'b0 : 1'bz;
  assign sda        = (sda_ena_n == 1'b0)  ? 1'b0 : 1'bz;

  always @(posedge clk, negedge reset_n) begin
    if (~reset_n) begin    // reset asserted
      stretch <= 1'b0;
      count = 0;
    end else begin
      data_clk_prev <= data_clk;
      if (count == divider*4-1) begin  // end of timing cycle
        count = 0;
      end else if (stretch == 1'b0) begin  // clock stretching from slave not detected
        count = count + 1;
      end
      
      if(count >= 0 && count <= divider -1) begin 
        scl_clk <= 1'b0;
        data_clk <= 1'b0;
      end else if(count >= divider && count <= divider*2-1) begin
        scl_clk <= 1'b0;
        data_clk <= 1'b1;
      end else if(count >= divider*2 && count <= divider*3-1) begin
        scl_clk <= 1'b1;
        if(scl == 0) begin
          stretch <= 1'b1;
        end else begin
          stretch <= 1'b0;
        end
        data_clk <= 1'b1;
      end else begin  
        scl_clk <= 1'b1;
        data_clk <= 1'b0;
      end
    end
  end

  always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin                 // reset asserted
    state <= ready;                   // return to initial state
    busy <= 1'b0;                     // indicate not available
    scl_ena <= 1'b0;                  // sets scl high impedance
    sda_int <= 1'b1;                  // sets sda high impedance
    ack_error <= 1'b0;                // clear acknowledge error flag
    bit_cnt <= 3'b111;                // restarts data bit counter
    data_rd <= 8'b00000000;           // clear data read port
  end else begin
    if ((data_clk & !data_clk_prev)) begin  // data clock rising edge
      case (state)
        ready: begin                   // idle state
          if (ena) begin               // transaction requested
            busy <= 1'b1;              // flag busy
            addr_rw <= {addr, rw};     // collect requested slave address and command
            data_tx <= data_wr;        // collect requested data to write
            state <= start;            // go to start bit
          end else begin               // remain idle
            busy <= 1'b0;              // unflag busy
            state <= ready;            // remain idle
          end
        end
        start: begin                   // start bit of transaction
          busy <= 1'b1;                // resume busy if continuous mode
          sda_int <= addr_rw[bit_cnt]; // set first address bit to bus
          state <= command;            // go to command
        end
        command: begin                 // address and command byte of transaction
          if (bit_cnt == 3'b000) begin // command transmit finished
            sda_int <= 1'b1;           // release sda for slave acknowledge
            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
            state <= slv_ack1;         // go to slave acknowledge (command)
          end else begin               // next clock cycle of command state
            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
            sda_int <= addr_rw[bit_cnt-1]; // write address/command bit to bus
            state <= command;          // continue with command
          end
        end
        slv_ack1: begin               // slave acknowledge bit (command)
          if (addr_rw[0] == 1'b0) begin // write command
            sda_int <= data_tx[bit_cnt]; // write first bit of data
            state <= wr;               // go to write byte
          end else begin               // read command
            sda_int <= 1'b1;           // release sda from incoming data
            state <= rd;               // go to read byte
          end
        end
        wr: begin                     // write byte of transaction
          busy <= 1'b1;               // resume busy if continuous mode
          if (bit_cnt == 3'b000) begin // write byte transmit finished
            sda_int <= 1'b1;           // release sda for slave acknowledge
            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
            state <= slv_ack2;         // go to slave acknowledge (write)
          end else begin               // next clock cycle of write state
            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
            sda_int <= data_tx[bit_cnt-1]; // write next bit to bus
            state <= wr;               // continue writing
          end
        end
        rd: begin                     // read byte of transaction
          busy <= 1'b1;               // resume busy if continuous mode
          if (bit_cnt == 3'b000) begin // read byte receive finished
            if (ena & (addr_rw == {addr, rw})) begin // continuing with another read at same address
              sda_int <= 1'b0;         // acknowledge the byte has been received
            end else begin             // stopping or continuing with a write
              sda_int <= 1'b1;         // send a no-acknowledge (before stop or repeated start)
            end
            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
            data_rd <= data_rx;        // output received data
            state <= mstr_ack;         // go to master acknowledge
          end else begin               // next clock cycle of read state
            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
            state <= rd;               // continue reading
          end
        end
        slv_ack2: begin               // slave acknowledge bit (write)
          if (ena) begin               // continue transaction
            busy <= 1'b0;              // continue is accepted
            addr_rw <= {addr, rw};     // collect requested slave address and command
            data_tx <= data_wr;        // collect requested data to write
            if (addr_rw == {addr, rw}) begin // continue transaction with another write
              sda_int <= data_wr[bit_cnt]; // write first bit of data
              state <= wr;             // go to write byte
            end else begin             // continue transaction with a read or new slave
              state <= start;          // go to repeated start
            end
          end else begin               // complete transaction
            state <= stop;             // go to stop bit
          end
        end
        mstr_ack: begin               // master acknowledge bit after a read
          if (ena) begin               // continue transaction
            busy <= 1'b0;              // continue is accepted and data received is available on bus
            addr_rw <= {addr, rw};     // collect requested slave address and command
            data_tx <= data_wr;        // collect requested data to write
            if (addr_rw == {addr, rw}) begin // continue transaction with another read
              sda_int <= 1'b1;         // release sda from incoming data
              state <= rd;             // go to read byte
            end else begin             // continue transaction with a write or new slave
              state <= start;          // repeated start
            end
          end else begin               // complete transaction
            state <= stop;             // go to stop bit
          end
        end
        stop: begin                   // stop bit of transaction
          busy <= 1'b0;               // unflag busy
          state <= ready;             // go to idle state
        end
        
      endcase
    end else if ((!data_clk & data_clk_prev)) begin  // data clock falling edge
      case (state)
        start: begin
          if (!scl_ena) begin                // starting new transaction
            scl_ena <= 1'b1;                 // enable scl output
            ack_error <= 1'b0;               // reset acknowledge error output
          end
        end
        slv_ack1: begin                      // receiving slave acknowledge (command)
          if ((sda != 1'b0) | ack_error) begin  // no-acknowledge or previous no-acknowledge
            ack_error <= 1'b1;                 // set error output if no-acknowledge
          end
        end
        rd: begin                            // receiving slave data
          data_rx[bit_cnt] <= sda;           // receive current slave data bit
        end
        slv_ack2: begin                      // receiving slave acknowledge (write)
          if ((sda != 1'b0) | ack_error) begin  // no-acknowledge or previous no-acknowledge
            ack_error <= 1'b1;                 // set error output if no-acknowledge
          end
        end
        stop: begin
          scl_ena <= 1'b0;                    // disable scl
        end
        
      endcase
    end
  end
end

// set sda output
always @(*) begin
  case (state)
    start: sda_ena_n <= data_clk_prev; // generate start condition
    stop: sda_ena_n <= ~data_clk_prev; // generate stop condition
    default: sda_ena_n <= sda_int;     // set to internal sda signal
  endcase
end

   
endmodule
















//#(
//parameter input_clk = 25_000_000,      //--input clock speed from user logic in Hz
//parameter bus_clk   = 400_000    // --speed the i2c bus (scl) will run at in Hz

//)(
//input           clk         ,                //--system clock
//input           reset_n     ,                // --active low reset
//input           ena         ,                // --latch in command
//input     [6:0] addr        ,    // --address of target slave
//input           rw          ,                        // --'0' is write, '1' is read
//input     [7:0] data_wr     ,          // --data to write to slave
//output reg      busy        ,                     // --indicates transaction in progress
//output reg[7:0] data_rd     ,        // --data read from slave
//output wire      ack_error   ,     //buffer  : BUFFER STD_LOGIC;                         // --flag if improper acknowledge from slave
//inout           sda         ,                // --serial data output of i2c bus
//inout           scl                           // --serial clock output of i2c bus
//    );
                           
//reg data_clk                ;                      //--data clock for sda                        
//reg data_clk_prev           ;                      //--data clock during previous system clock   
//reg scl_clk                 ;                      //--constantly running internal scl           
//reg scl_ena       = 0       ;                     //--enables internal scl to output            
//reg sda_int       = 1       ;                      //--internal sda                              
//reg sda_ena_n               ;                      //--enables internal sda to output            
//reg[7:0] addr_rw            ;                     //--latched in address and read/write         
//reg[7:0] data_tx            ;                       //--latched in data to write to slave         
//reg[7:0] data_rx            ;                      //--data received from slave                  
//reg[3:0] bit_cnt            ;                      // INTEGER RANGE 0 TO 7 := 7;      //--tracks bit number in transaction          
//reg stretch      = 0        ;                       //--identifies if slave is stretching scl     
//reg ack_error_r = 0;
//wire sda_1;
//wire sda_2;


//reg [31:0] count;
//   // ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop
// reg [3:0] state;   
//localparam ready    = 4'b0000;
//localparam start    = 4'b0001;    
//localparam command  = 4'b0010;
//localparam slv_ack1 = 4'b0011;
//localparam wr       = 4'b0100;
//localparam rd       = 4'b0101;
//localparam slv_ack2 = 4'b0110;
//localparam mstr_ack = 4'b0111;
//localparam stop     = 4'b1000;
 
//localparam divider = (input_clk/bus_clk);



//always @(posedge clk, negedge reset_n) begin
//  if (~reset_n) begin    // reset asserted
//    stretch <= 1'b0;
//    count <= 0;
//  end else begin
//    data_clk_prev <= data_clk;
//    if (count == divider*4-1) begin  // end of timing cycle
//      count <= 0;
//    end else if (stretch == 1'b0) begin  // clock stretching from slave not detected
//      count <= count + 1;
//    end
    
//    if(count >= 0 && count <= divider -1) begin 
//        scl_clk <= 1'b0;
//        data_clk <= 1'b0;
//    end else if(count >= divider && count <= divider*2-1) begin
        
//        scl_clk <= 1'b0;
//        data_clk <= 1'b1;
        
//    end else if(count >= divider*2 && count <= divider*3-1) begin
    
//        scl_clk <= 1'b1;
//        if(scl == 0) begin
        
//            stretch <= 1'b1;
        
//        end else begin
        
//            stretch <= 1'b0;
        
//        end
//        data_clk <= 1'b1;
       
//    end 
//    if(count >= divider*3) begin
    
//        scl_clk <= 1'b1;
//        data_clk <= 1'b0;
    
//    end
    
    
//  end
//end

//  always @(posedge clk or negedge reset_n) begin
//  if (~reset_n) begin                 // reset asserted
//    state <= ready;                   // return to initial state
//    busy <= 1'b0;                     // indicate not available
//    scl_ena <= 1'b0;                  // sets scl high impedance
//    sda_int <= 1'b1;                  // sets sda high impedance
//    ack_error_r <= 1'b0;                // clear acknowledge error flag
//    bit_cnt <= 3'b111;                // restarts data bit counter
//    data_rd <= 8'b00000000;           // clear data read port
//  end else begin
//    if ((data_clk & !data_clk_prev)) begin  // data clock rising edge
//      case (state)
//        ready: begin                   // idle state
//          if (ena) begin               // transaction requested
//            busy <= 1'b1;              // flag busy
//            addr_rw <= {addr, rw};     // collect requested slave address and command
//            data_tx <= data_wr;        // collect requested data to write
//            state <= start;            // go to start bit
//          end else begin               // remain idle
//            busy <= 1'b0;              // unflag busy
//            state <= ready;            // remain idle
//          end
//        end
//        start: begin                   // start bit of transaction
//          busy <= 1'b1;                // resume busy if continuous mode
//          sda_int <= addr_rw[bit_cnt]; // set first address bit to bus
//          state <= command;            // go to command
//        end
//        command: begin                 // address and command byte of transaction
//          if (bit_cnt == 3'b000) begin // command transmit finished
//            sda_int <= 1'b1;           // release sda for slave acknowledge
//            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
//            state <= slv_ack1;         // go to slave acknowledge (command)
//          end else begin               // next clock cycle of command state
//            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
//            sda_int <= addr_rw[bit_cnt-1]; // write address/command bit to bus
//            state <= command;          // continue with command
//          end
//        end
//        slv_ack1: begin               // slave acknowledge bit (command)
//          if (addr_rw[0] == 1'b0) begin // write command
//            sda_int <= data_tx[bit_cnt]; // write first bit of data
//            state <= wr;               // go to write byte
//          end else begin               // read command
//            sda_int <= 1'b1;           // release sda from incoming data
//            state <= rd;               // go to read byte
//          end
//        end
//        wr: begin                     // write byte of transaction
//          busy <= 1'b1;               // resume busy if continuous mode
//          if (bit_cnt == 3'b000) begin // write byte transmit finished
//            sda_int <= 1'b1;           // release sda for slave acknowledge
//            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
//            state <= slv_ack2;         // go to slave acknowledge (write)
//          end else begin               // next clock cycle of write state
//            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
//            sda_int <= data_tx[bit_cnt-1]; // write next bit to bus
//            state <= wr;               // continue writing
//          end
//        end
//        rd: begin                     // read byte of transaction
//          busy <= 1'b1;               // resume busy if continuous mode
//          if (bit_cnt == 3'b000) begin // read byte receive finished
//            if (ena & (addr_rw == {addr, rw})) begin // continuing with another read at same address
//              sda_int <= 1'b0;         // acknowledge the byte has been received
//            end else begin             // stopping or continuing with a write
//              sda_int <= 1'b1;         // send a no-acknowledge (before stop or repeated start)
//            end
//            bit_cnt <= 3'b111;         // reset bit counter for "byte" states
//            data_rd <= data_rx;        // output received data
//            state <= mstr_ack;         // go to master acknowledge
//          end else begin               // next clock cycle of read state
//            bit_cnt <= bit_cnt - 1;    // keep track of transaction bits
//            state <= rd;               // continue reading
//          end
//        end
//        slv_ack2: begin               // slave acknowledge bit (write)
//          if (ena) begin               // continue transaction
//            busy <= 1'b0;              // continue is accepted
//            addr_rw <= {addr, rw};     // collect requested slave address and command
//            data_tx <= data_wr;        // collect requested data to write
//            if (addr_rw == {addr, rw}) begin // continue transaction with another write
//              sda_int <= data_wr[bit_cnt]; // write first bit of data
//              state <= wr;             // go to write byte
//            end else begin             // continue transaction with a read or new slave
//              state <= start;          // go to repeated start
//            end
//          end else begin               // complete transaction
//            state <= stop;             // go to stop bit
//          end
//        end
//        mstr_ack: begin               // master acknowledge bit after a read
//          if (ena) begin               // continue transaction
//            busy <= 1'b0;              // continue is accepted and data received is available on bus
//            addr_rw <= {addr, rw};     // collect requested slave address and command
//            data_tx <= data_wr;        // collect requested data to write
//            if (addr_rw == {addr, rw}) begin // continue transaction with another read
//              sda_int <= 1'b1;         // release sda from incoming data
//              state <= rd;             // go to read byte
//            end else begin             // continue transaction with a write or new slave
//              state <= start;          // repeated start
//            end
//          end else begin               // complete transaction
//            state <= stop;             // go to stop bit
//          end
//        end
//        stop: begin                   // stop bit of transaction
//          busy <= 1'b0;               // unflag busy
//          state <= ready;             // go to idle state
//        end
        
//      endcase
//    end else if ((!data_clk & data_clk_prev)) begin  // data clock falling edge
//      case (state)
//        start: begin
//          if (~scl_ena) begin                // starting new transaction
//            scl_ena <= 1'b1;                 // enable scl output
//            ack_error_r <= 1'b0;               // reset acknowledge error output
//          end
//        end
//        slv_ack1: begin                      // receiving slave acknowledge (command)
//          if ((sda != 1'b0) | ack_error_r) begin  // no-acknowledge or previous no-acknowledge
//            ack_error_r <= 1'b1;                 // set error output if no-acknowledge
//          end
//        end
//        rd: begin                            // receiving slave data
//          data_rx[bit_cnt] <= sda;           // receive current slave data bit
//        end
//        slv_ack2: begin                      // receiving slave acknowledge (write)
//          if ((sda != 1'b0) | ack_error_r) begin  // no-acknowledge or previous no-acknowledge
//            ack_error_r <= 1'b1;                 // set error output if no-acknowledge
//          end
//        end
//        stop: begin
//          scl_ena <= 1'b0;                    // disable scl
//        end
        
//      endcase
//    end
//  end
//end

//// set sda output
//always @(*) begin
//  case (state)
//    start: sda_ena_n <= data_clk_prev; // generate start condition
//    stop: sda_ena_n <= ~data_clk_prev; // generate stop condition
//    default: sda_ena_n <= sda_int;     // set to internal sda signal
//  endcase
//end

//assign scl        = (scl_ena & ~scl_clk) ? 1'b0 : 1'bz;
//assign sda_1      = (sda_ena_n == 1'b0) ? 1'b0 : 1'bz;
//assign sda        = sda_1;
//assign ack_error  = ack_error_r;

//// set scl and sda outputs
////assign scl = (scl_ena & ~scl_clk) ? 1'b0 : 1'bz;
////assign sda_1 = (sda_ena_n == 1'b0) ? 1'b0 : 1'bz;
////assign sda_2 = sda_1;
////assign sda = sda_2;
//// assign ack_error = ack_error_r;
   
//endmodule




