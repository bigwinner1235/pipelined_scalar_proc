module DataMemory #(parameter ADDR_BITS = 16)(
    input write_enable, read_enable, clk,
    input [63:0] address, data_in,
    input [2:0] funct3,
    output reg [63:0] data_out
);
reg [7:0] mem0 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem1 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem2 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem3 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem4 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem5 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem6 [(1 << (ADDR_BITS - 3)) - 1:0];
reg [7:0] mem7 [(1 << (ADDR_BITS - 3)) - 1:0];

wire [ADDR_BITS - 1:0] adjusted_address = address[ADDR_BITS - 1:0];
wire [ADDR_BITS - 1:3] row = adjusted_address[ADDR_BITS - 1:3];
wire [1:0] size = funct3[1:0];
wire not_signed = funct3[2];

reg sustained_read_enable, sustained_not_signed;
reg [2:0] sustained_size, sustained_offset;

always @(posedge clk) begin
    sustained_read_enable <= read_enable;
    sustained_not_signed <= not_signed;
    sustained_size <= size;
    sustained_offset <= adjusted_address[2:0];
end

reg [63:0] raw;
always @ (posedge clk) begin
    raw <= {mem7[row], mem6[row], mem5[row], mem4[row],
            mem3[row], mem2[row], mem1[row], mem0[row]};
end

always @(*) begin
    if(sustained_read_enable) begin
        if(sustained_size == 2'd0) begin
            data_out = sustained_not_signed?    {56'd0,raw[8*sustained_offset +: 8]} : 
                                                {{56{raw[7 + 8*sustained_offset]}},raw[8*sustained_offset +: 8]};
        end
        else if(sustained_size == 2'd1 && sustained_offset <= 3'd6) begin
            data_out = sustained_not_signed?    {48'd0,raw[8*sustained_offset +: 16]} : 
                                                {{48{raw[15 + 8*sustained_offset]}},raw[8*sustained_offset +: 16]};
        end
        else if(sustained_size == 2'd2 && sustained_offset <= 3'd4) begin
            data_out = sustained_not_signed?    {32'd0,raw[8*sustained_offset +: 32]} : 
                                                {{32{raw[31 + 8*sustained_offset]}},raw[8*sustained_offset +: 32]};
        end
        else if(sustained_size == 2'd3 && sustained_offset == 3'd0) begin
            data_out = raw;
        end
        else begin
            data_out = 64'd0;
            //maybe exception for misaligned access here
        end
    end
    else
        data_out = 64'd0;
end

always @(posedge clk) begin
    if(write_enable) begin
        if(size == 2'd0) begin
            case(adjusted_address[2:0])
                3'd0: mem0[row] <= data_in[7:0];
                3'd1: mem1[row] <= data_in[7:0];
                3'd2: mem2[row] <= data_in[7:0];
                3'd3: mem3[row] <= data_in[7:0];
                3'd4: mem4[row] <= data_in[7:0];
                3'd5: mem5[row] <= data_in[7:0];
                3'd6: mem6[row] <= data_in[7:0];
                3'd7: mem7[row] <= data_in[7:0];
            endcase
        end
        else if(size == 2'd1 && adjusted_address[2:0] <= 3'd6) begin
            case(adjusted_address[2:0])
                3'd0: {mem1[row], mem0[row]} <= data_in[15:0];
                3'd1: {mem2[row], mem1[row]} <= data_in[15:0];
                3'd2: {mem3[row], mem2[row]} <= data_in[15:0];
                3'd3: {mem4[row], mem3[row]} <= data_in[15:0];
                3'd4: {mem5[row], mem4[row]} <= data_in[15:0];
                3'd5: {mem6[row], mem5[row]} <= data_in[15:0];
                3'd6: {mem7[row], mem6[row]} <= data_in[15:0];
            endcase
        end
        else if(size == 2'd2 && adjusted_address[2:0] <= 3'd4) begin
            case(adjusted_address[2:0])
                3'd0: {mem3[row], mem2[row], mem1[row], mem0[row]} <= data_in[31:0];
                3'd1: {mem4[row], mem3[row], mem2[row], mem1[row]} <= data_in[31:0];
                3'd2: {mem5[row], mem4[row], mem3[row], mem2[row]} <= data_in[31:0];
                3'd3: {mem6[row], mem5[row], mem4[row], mem3[row]} <= data_in[31:0];
                3'd4: {mem7[row], mem6[row], mem5[row], mem4[row]} <= data_in[31:0];
            endcase
        end
        else if(size == 2'd3 && adjusted_address[2:0] == 3'd0) begin
            {mem7[row], mem6[row], mem5[row], mem4[row],
             mem3[row], mem2[row], mem1[row], mem0[row]} <= data_in;
        end
    end
end

endmodule
