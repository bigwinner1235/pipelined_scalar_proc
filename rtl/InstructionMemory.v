module InstructionMemory #(parameter ADDR_BITS = 16) (
    input  clk,
    input  enable,
    input  [63:0] address,
    output reg [31:0] inst
);

(* rom_style = "block" *) reg [7:0] mem0 [(1 << (ADDR_BITS - 2)) - 1 : 0];
(* rom_style = "block" *) reg [7:0] mem1 [(1 << (ADDR_BITS - 2)) - 1 : 0];
(* rom_style = "block" *) reg [7:0] mem2 [(1 << (ADDR_BITS - 2)) - 1 : 0];
(* rom_style = "block" *) reg [7:0] mem3 [(1 << (ADDR_BITS - 2)) - 1 : 0];

wire [ADDR_BITS-1:0] a = address[ADDR_BITS-1:0];
wire [ADDR_BITS-1:2] row = a[ADDR_BITS-1:2];
wire [1:0] offset = a[1:0];

//instruction addresses must be aligned to 4 bytes
always @(posedge clk) begin
    if(enable)
        if(offset == 2'd0)
            begin
                inst <= {mem3[row], mem2[row], mem1[row], mem0[row]};
            end
        else
            begin
                //maybe should trigger an exception here
                inst <= 32'h00000013; // NOP
            end
end


`ifndef SIMULATION
initial begin
    $readmemh("C:/Users/Jack R/Documents/pipelined_scalar_proc/pipelined_scalar_proc/tests/fib16/imem0.hex", mem0);
    $readmemh("C:/Users/Jack R/Documents/pipelined_scalar_proc/pipelined_scalar_proc/tests/fib16/imem1.hex", mem1);
    $readmemh("C:/Users/Jack R/Documents/pipelined_scalar_proc/pipelined_scalar_proc/tests/fib16/imem2.hex", mem2);
    $readmemh("C:/Users/Jack R/Documents/pipelined_scalar_proc/pipelined_scalar_proc/tests/fib16/imem3.hex", mem3);
end
`endif
endmodule