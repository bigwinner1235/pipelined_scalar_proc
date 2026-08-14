//Claude wrote this
`timescale 1ns/1ps
module tb_top;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  PipelinedTopLevel dut (
    .clk(clk),
    .reset(rst),
    .startpc(64'd0)
  );

  // a test program ends one of two ways:
  //   - ecall/ebreak or an illegal instruction, which latches dut.halt in MEM
  //   - "jal x0, 0" (a self-loop); done when that instruction reaches WB
  // either way every earlier instruction has already written back and any
  // store it made has already committed in MEM.
  localparam [31:0] HALT_INST = 32'h0000006f;
  localparam        MAX_CYCLES = 10000;

  reg [1023:0] testdir, path;
  integer fd, r, errors, cycles, i, budget;
  integer exp_halt, exp_illegal;
  reg [63:0] addr, expect_val, actual;
  reg halted, got_flags;

  // read 8 bytes little-endian out of the byte-addressed data memory
  function [63:0] read_dmem(input [63:0] a);
    integer k;
    begin
      read_dmem = 64'd0;
      for (k = 0; k < 8; k = k + 1)
        read_dmem[8*k +: 8] = dut.data_mem.mem[a + k];
    end
  endfunction

  initial begin
    if (!$value$plusargs("testdir=%s", testdir)) begin
      $display("ERROR: no +testdir given");
      $finish;
    end

    // clear instruction memory so unfilled words read as 0, not X
    for (i = 0; i < (1<<16); i = i + 1)
      dut.imem.mem[i] = 8'h00;

    $sformat(path, "%0s/prog.hex", testdir);
    $readmemh(path, dut.imem.mem);

    if ($test$plusargs("vcd")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end

    // hold reset, then release on a negedge so the release is clean
    repeat (4) @(posedge clk);
    @(negedge clk);
    // clear data memory here, not at time 0: the core executes instruction 0
    // repeatedly while reset is held, so any stores it does must be wiped.
    for (i = 0; i < (1<<16); i = i + 1)
      dut.data_mem.mem[i] = 8'h00;
    rst = 0;

    // run until the core halts or the self-loop retires, or until we time out
    halted = 1'b0;
    for (cycles = 0; cycles < MAX_CYCLES && !halted; cycles = cycles + 1) begin
      @(negedge clk);
      if (dut.halt === 1'b1 || dut.wb_instruction === HALT_INST) halted = 1'b1;
    end

    if (!halted) begin
      $display("  core did not halt within %0d cycles", MAX_CYCLES);
      $display("TEST FAILED (timeout)");
      $finish;
    end

    $display("  program finished in %0d cycles (halt=%b illegal=%b)",
             cycles, dut.halt, dut.illegal);

    errors = 0;
    $sformat(path, "%0s/expected.txt", testdir);
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %0s", path);
      $finish;
    end

    while (!$feof(fd)) begin
      r = $fscanf(fd, " %h %h", addr, expect_val);
      if (r == 2) begin
        actual = read_dmem(addr);
        if (actual !== expect_val) begin
          $display("  mem[0x%h] = 0x%h, expected 0x%h", addr, actual, expect_val);
          errors = errors + 1;
        end
      end else begin
        r = $fgets(path, fd);
      end
    end
    $fclose(fd);

    // trap flags: every test states what halt and illegal_instruction must be
    // when the program stops, so a legal program is checked for staying quiet
    // just as strictly as a trapping one is checked for firing.
    $sformat(path, "%0s/flags.txt", testdir);
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %0s", path);
      $finish;
    end
    got_flags = 1'b0;
    exp_halt = 0;
    exp_illegal = 0;
    while (!$feof(fd) && !got_flags) begin
      r = $fscanf(fd, " %d %d", exp_halt, exp_illegal);
      if (r == 2) got_flags = 1'b1;
      else        r = $fgets(path, fd);
    end
    $fclose(fd);

    if (!got_flags) begin
      $display("ERROR: %0s/flags.txt has no 'halt illegal' line", testdir);
      $finish;
    end

    if ((dut.halt === 1'b1) !== (exp_halt != 0)) begin
      $display("  halt = %b, expected %0d", dut.halt, exp_halt);
      errors = errors + 1;
    end
    if ((dut.illegal === 1'b1) !== (exp_illegal != 0)) begin
      $display("  illegal_instruction = %b, expected %0d", dut.illegal, exp_illegal);
      errors = errors + 1;
    end

    // optional cycle budget: perf regression tests fail if they get slower
    $sformat(path, "%0s/max_cycles.txt", testdir);
    fd = $fopen(path, "r");
    if (fd != 0) begin
      r = $fscanf(fd, " %d", budget);
      $fclose(fd);
      if (r == 1 && cycles > budget) begin
        $display("  took %0d cycles, budget is %0d", cycles, budget);
        errors = errors + 1;
      end
    end

    if (errors == 0) $display("TEST PASSED");
    else                     $display("TEST FAILED (%0d mismatches)", errors);
    $finish;
  end
endmodule
