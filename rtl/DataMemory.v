module DataMemory #(parameter ADDR_BITS = 16)(
    input write_enable, read_enable, clk,
    input [63:0] address, data_in,
    input [2:0] funct3,
    output reg [63:0] data_out
);
/*
2^ADDR_BITS bytes of synchronous memory.
The memory is organized into 8 banks, each bank is 1 byte wide, and the banks are interleaved across memory 
i.e. the nth bank stores bytes n, n+8, n+16, etc. This means that accesses to certain bytes are restricted 
in the size they can be to avoid misaligned accesses. Ex.
    8-bit accesses can be made to any byte
    16-bit accesses can be made to bytes in bank 0,1,2,3,4,5,6
    32-bit accesses can be made to bytes in bank 0,1,2,3,4
    64-bit accesses can only be made to bytes in bank 0
*/


(* ram_style = "block" *) reg [7:0] mem0 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem1 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem2 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem3 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem4 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem5 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem6 [(1 << (ADDR_BITS - 3)) - 1:0];
(* ram_style = "block" *) reg [7:0] mem7 [(1 << (ADDR_BITS - 3)) - 1:0];

wire [ADDR_BITS - 1:0] adjusted_address = address[ADDR_BITS - 1:0];
wire [ADDR_BITS - 1:3] row = adjusted_address[ADDR_BITS - 1:3];
wire [1:0] size = funct3[1:0];
wire not_signed = funct3[2];

//reads implemented as load an entire row, then select appropriate bytes.
//this requires latching the appropriate signals:
reg sustained_read_enable, sustained_not_signed;
reg [2:0] sustained_size, sustained_offset;
always @(posedge clk) begin
    sustained_read_enable <= read_enable;
    sustained_not_signed <= not_signed;
    sustained_size <= size;
    sustained_offset <= adjusted_address[2:0];
end



reg [63:0] raw;
reg [7:0] wen; //write enable for each bank
reg [7:0] data0, data1, data2, data3, data4, data5, data6, data7;

//enable gated read/write mechanism
always @ (posedge clk) begin
    if(wen[0]) begin
        mem0[row] <= data0;
    end
    if(wen[1]) begin
        mem1[row] <= data1;
    end
    if(wen[2]) begin
        mem2[row] <= data2;
    end
    if(wen[3]) begin
        mem3[row] <= data3;
    end
    if(wen[4]) begin
        mem4[row] <= data4;
    end
    if(wen[5]) begin
        mem5[row] <= data5;
    end
    if(wen[6]) begin
        mem6[row] <= data6;
    end
    if(wen[7]) begin
        mem7[row] <= data7;
    end
    if(read_enable) begin
        raw <= {mem7[row], mem6[row], mem5[row], mem4[row],
                mem3[row], mem2[row], mem1[row], mem0[row]};
    end
end

// write bank routing logic
always @(*) begin
    wen = 8'b0;
    {data7, data6, data5, data4, data3, data2, data1, data0} = 64'd0;
    if(write_enable) begin
        if(size == 2'd0) begin
            case(adjusted_address[2:0])
                3'd0: begin
                    wen[0] = 1'b1;
                    data0 = data_in[7:0];
                end
                3'd1: begin
                    wen[1] = 1'b1;
                    data1 = data_in[7:0];
                end
                3'd2: begin
                    wen[2] = 1'b1;
                    data2 = data_in[7:0];
                end
                3'd3: begin
                    wen[3] = 1'b1;
                    data3 = data_in[7:0];
                end
                3'd4: begin
                    wen[4] = 1'b1;
                    data4 = data_in[7:0];
                end
                3'd5: begin
                    wen[5] = 1'b1;
                    data5 = data_in[7:0];
                end
                3'd6: begin
                    wen[6] = 1'b1;
                    data6 = data_in[7:0];
                end
                3'd7: begin
                    wen[7] = 1'b1;
                    data7 = data_in[7:0];
                end
            endcase
        end
        else if(size == 2'd1 && adjusted_address[2:0] <= 3'd6) begin
            case(adjusted_address[2:0])
                3'd0: begin
                    wen[1:0] = 2'b11;
                    data0 = data_in[7:0];
                    data1 = data_in[15:8];
                end
                3'd1: begin
                    wen[2:1] = 2'b11;
                    data1 = data_in[7:0];
                    data2 = data_in[15:8];
                end
                3'd2: begin
                    wen[3:2] = 2'b11;
                    data2 = data_in[7:0];
                    data3 = data_in[15:8];
                end
                3'd3: begin
                    wen[4:3] = 2'b11;
                    data3 = data_in[7:0];
                    data4 = data_in[15:8];
                end
                3'd4: begin
                    wen[5:4] = 2'b11;
                    data4 = data_in[7:0];
                    data5 = data_in[15:8];
                end
                3'd5: begin
                    wen[6:5] = 2'b11;
                    data5 = data_in[7:0];
                    data6 = data_in[15:8];
                end
                3'd6: begin
                    wen[7:6] = 2'b11;
                    data6 = data_in[7:0];
                    data7 = data_in[15:8];
                end
            endcase
        end
        else if(size == 2'd2 && adjusted_address[2:0] <= 3'd4) begin
            case(adjusted_address[2:0])
                3'd0: begin
                    wen[3:0] = 4'b1111;
                    data0 = data_in[7:0];
                    data1 = data_in[15:8];
                    data2 = data_in[23:16];
                    data3 = data_in[31:24];
                end
                3'd1: begin
                    wen[4:1] = 4'b1111;
                    data1 = data_in[7:0];
                    data2 = data_in[15:8];
                    data3 = data_in[23:16];
                    data4 = data_in[31:24];
                end
                3'd2: begin
                    wen[5:2] = 4'b1111;
                    data2 = data_in[7:0];
                    data3 = data_in[15:8];
                    data4 = data_in[23:16];
                    data5 = data_in[31:24];
                end
                3'd3: begin
                    wen[6:3] = 4'b1111;
                    data3 = data_in[7:0];
                    data4 = data_in[15:8];
                    data5 = data_in[23:16];
                    data6 = data_in[31:24];
                end
                3'd4: begin
                    wen[7:4] = 4'b1111;
                    data4 = data_in[7:0];
                    data5 = data_in[15:8];
                    data6 = data_in[23:16];
                    data7 = data_in[31:24];
                end
            endcase
        end
        else if(size == 2'd3 && adjusted_address[2:0] == 3'd0) begin
            wen = 8'b11111111;
            {data7, data6, data5, data4, data3, data2, data1, data0} = data_in;
        end
    end
end


//read concatination logic
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


endmodule