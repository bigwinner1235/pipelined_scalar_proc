module DataMemory #(parameter ADDR_BITS = 16)(
    input write_enable, read_enable, clk,
    input [63:0] address, data_in,
    input [2:0] funct3,
    output reg [63:0] data_out
);
reg [7:0] mem [(1 << ADDR_BITS) - 1:0];
wire [ADDR_BITS - 1:0] adjusted_address = address[ADDR_BITS - 1:0];
wire [1:0] size = funct3[1:0];
wire not_signed = funct3[2];
wire [63:0] raw = {mem[adjusted_address+7], mem[adjusted_address+6], mem[adjusted_address+5], mem[adjusted_address+4],
                   mem[adjusted_address+3], mem[adjusted_address+2], mem[adjusted_address+1], mem[adjusted_address+0]};
always @(posedge clk) begin
    if(read_enable) begin
        case(size)
            2'd0: data_out <= not_signed? {56'd0,raw[7:0]} : {{56{raw[7]}},raw[7:0]};
            2'd1: data_out <= not_signed? {48'd0,raw[15:0]} : {{48{raw[15]}},raw[15:0]};
            2'd2: data_out <= not_signed? {32'd0,raw[31:0]} : {{32{raw[31]}},raw[31:0]};
            2'd3: data_out <= raw;
            default: data_out <= 64'd0;
        endcase
    end
    else data_out = 64'd0;
end
always @(posedge clk) begin
    if(write_enable) begin
        mem[adjusted_address] <= data_in[7:0];
        if(size >= 1)
            mem[adjusted_address + 3'd1] <= data_in[15:8];
        if(size >= 2) begin   
            mem[adjusted_address + 3'd2] <= data_in[23:16]; 
            mem[adjusted_address + 3'd3] <= data_in[31:24];
        end
        if(size == 3) begin
            mem[adjusted_address + 3'd4] <= data_in[39:32];
            mem[adjusted_address + 3'd5] <= data_in[47:40];
            mem[adjusted_address + 3'd6] <= data_in[55:48];
            mem[adjusted_address + 3'd7] <= data_in[63:56];
        end
    end
end

endmodule