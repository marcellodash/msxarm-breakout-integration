/*
  MSXARM & slim/fat breakout board interface
  
  Opensource, license CC BY-NC-SA 3.0 - Creative Commons: http://creativecommons.org/licenses/by-nc-sa/3.0
  
  Warning: We have 2 clock domains: FPGA clock(33Mhz) and Z80 clock (3.58Mhz/7Mhz)
  
  */
module main(
  input           CLK,          // Clock max 16Mhz. Flat cable/PCB design limit
  
  output          ACT,          // Z80 (MREQ and IOREQ) -> FPGA. Z80 clock domain
  input  [2:0]    CMD,          // FPGA -> CPLD command
  inout  [7:0]    D,            // FPGA <-> CPLD data bus  
  
  input           SIGMA_IN,
  
  input           ZMREQ,        // Z80 MRED
  input           ZIOREQ,       // Z80 IOREQ
  input           ZM1,          // Z80 M1
  input           ZRD,          // Z80 READ. 
                                // Z80 WRITE. must be infered from RD signal
  input           ZSLTSL,       // MSX slot select
  output          ZBUSDIR,      // MSX busdir
  inout           ZINT,         // Z80 non-maskable interrupt. Open collector
  inout           ZWAIT,        // Z80 wait. Open collector
  
  input [15:0]    ZA,
  inout [7:0]     ZD,           // FPGA/CPLD data bus
  
  output reg [2:0] LED,         // RGB led

  output reg [1:0] SIGMA_OUT,   // Sigma delta modulation. Stereo
  
  inout            SNDCLK       // Dual function: LM4811 Audio chip volume control. Master reset
);

// FPGA -> CPLD commands
`define CMD_RD_SIGNALS      3'b000 
`define CMD_RD_LOW_ADDRESS  3'b001
`define CMD_RD_HIGH_ADDRESS 3'b010
`define CMD_RD_BUS          3'b011
`define CMD_WR_BUS          3'b100
`define CMD_WR_REG          3'b101

assign ACT = ZMREQ & ZIOREQ;

assign ZBUSDIR = 1; // TODO

reg [7:0] fdata;
reg [7:0] zdout;
reg fzint;
reg fwait;
reg freset;

assign SNDCLK = freset ?  1'b0 : 1'bz;

assign ZD[7:0] = ~(ZSLTSL & ZRD) ? zdout[7:0] : 8'bz;

// Z80 int. open colector
assign ZINT = fzint ?  1'b0 : 1'bz;

// Z80 wait
assign ZWAIT = fwait ? 1'b0 : 1'bz;

// dont use ZSLTSL. MSX logic <-> ZMREQ delay
assign parity1 = (^ZA[15:0]) ^ ZIOREQ ^ ZMREQ ^ ZRD ^ ZM1; 
assign parity2 = (^ZD[7:0]); 

assign D = (CMD[2] == 0) ? fdata[7:0] : 8'bz;

/*
Z80 signals MUST be loaded using combinatorial (Z80 clock domain). 
FPGA do the cross domain because it has much more resources
 */
always @(*)
begin
    case(CMD[2:0])
      `CMD_RD_SIGNALS:   // Z80 control signals
      begin
        // ZIOREQ must be infered from ACT signal
        fdata[7:0] = { 
                       parity1,   // Parity: Z80 address
                       parity2,   // Parity: Z80 data bus
                       1'b0,      // spare
                       1'b0,      // spare
                       1'b0,      // spare
                       ZMREQ,     // Z80 MREQ\
                       ZRD,       // Z80 RD\
                       ZM1        // Z80 M1\
                       };
      end
      
      `CMD_RD_LOW_ADDRESS:   // Z80 Low address
      begin
        fdata[7:0] = ZA[7:0];
      end
        
      `CMD_RD_HIGH_ADDRESS:   // Z80 High address
      begin
        fdata[7:0] = ZA[15:8];
      end
      
      `CMD_RD_BUS:   // Read Z80 data bus
      begin
        fdata[7:0] = ZD[7:0];
      end

      default:
      begin
        fdata[7:0] = { 
                       LED[2:0],
                       SNDCLK,
                       1'b0,
                       1'b0,
                       ZSLTSL,
                       ZINT
                      };      
      end  
    endcase
end

/* FPGA clock domain */
always @(posedge CLK)
begin
  // TODO: stereo sound
  SIGMA_OUT[1] = SIGMA_IN; // mono sound
  SIGMA_OUT[0] = SIGMA_IN; // mono sound
end

/* FPGA clock domain */
always @(posedge CLK or negedge SNDCLK)
begin
  if(SNDCLK == 0) begin
    // Assyncronous reset. 
    LED[2:1] <= 0; // LED RED/GREEN off
    fzint <= 1'b0;
    fwait <= 1'b0;
  end  
  else 
    case(CMD[2:0])
      `CMD_WR_BUS:   // Write Z80 data bus
      begin
        zdout[7:0] <= D[7:0];
      end
      
      `CMD_WR_REG:   // Write internal register
      begin
         LED[2:0] <= D[2:0]; // RGB led
         //
         fzint <= D[4];      // Z80 interrupt
         freset <= D[5];     // Dual function: Volume clock, master reset
      end
    endcase
end

endmodule
