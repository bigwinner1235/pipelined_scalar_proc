module ProcWrapper (
    input clk, rst,
    output halt, illegal, UART
);
// if i even need all of these
wire data_mem_write_enable;
wire [63:0] data_mem_address;
wire [63:0] data_mem_data_in;
wire [2:0] data_mem_funct3;

reg sync_rst0, sync_rst;
always @(posedge clk) begin
    sync_rst0 <= rst;
    sync_rst <= sync_rst0;
end

PipelinedTopLevel proc (
    .reset(sync_rst),
    .startpc(64'h0),
    .clk(clk),
    .halt(halt),
    .illegal(illegal),
    .data_mem_write_enable(data_mem_write_enable),
    .data_mem_address(data_mem_address),
    .data_mem_data_in(data_mem_data_in),
    .data_mem_funct3(data_mem_funct3)
);


reg [7:0] uart_data;
always @(*) begin
    if(data_mem_address == 64'h6969 && data_mem_write_enable) begin
        //fuckkkk I need a FIFO
    end
end


UART uart(
    // :/
);
endmodule