//improve synthesis
module ProcWrapper (
    input clk, rst,
    output halt, illegal, write
);

reg sync_rst0, sync_rst;
always @(posedge clk) begin
    sync_rst0 <= rst;
    sync_rst <= sync_rst0;
end

//more unused outputs could be used to see memory write history
PipelinedTopLevel proc (
    .reset(sync_rst),
    .startpc(64'h0),
    .clk(clk),
    .halt(halt),
    .illegal(illegal),
    .data_mem_write_enable(write)
);
endmodule