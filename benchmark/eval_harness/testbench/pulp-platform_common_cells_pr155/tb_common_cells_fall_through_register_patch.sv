`timescale 1ns/1ps

module tb_common_cells_fall_through_register_patch;

  // -------------------------------------------------------
  // Parameters and types
  // -------------------------------------------------------
  localparam int DATA_WIDTH = 16;
  typedef logic [DATA_WIDTH-1:0] data_t;

  localparam int NUM_RANDOM_TXNS = 50;
  localparam int CLK_PERIOD      = 10;

  // -------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------
  logic   clk;
  logic   rst_n;
  logic   clr;
  logic   testmode;
  logic   valid_i;
  logic   ready_o;
  data_t  data_i;
  logic   valid_o;
  logic   ready_i;
  data_t  data_o;

  // -------------------------------------------------------
  // Clock generation
  // -------------------------------------------------------
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -------------------------------------------------------
  // DUT: patched fall_through_register using fifo_v3
  // -------------------------------------------------------
  fall_through_register #(
    .T(data_t)
  ) i_ft_reg (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .clr_i      (clr),
    .testmode_i (testmode),
    .valid_i    (valid_i),
    .ready_o    (ready_o),
    .data_i     (data_i),
    .valid_o    (valid_o),
    .ready_i    (ready_i),
    .data_o     (data_o)
  );

  // -------------------------------------------------------
  // Scoreboard
  // -------------------------------------------------------
  data_t expected_queue[$];
  int pass_count;
  int fail_count;

  task automatic check_output(data_t expected);
    if (data_o !== expected) begin
      $display("FAIL: data_o = 0x%04h, expected 0x%04h at time %0t", data_o, expected, $time);
      fail_count++;
    end else begin
      pass_count++;
    end
  endtask

  // -------------------------------------------------------
  // Patch-focused covergroup (PR#155: fifo_v2 -> fifo_v3, add usage_o port)
  // -------------------------------------------------------
  covergroup cg_patch;
    cp_valid_i: coverpoint valid_i {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_ready_o: coverpoint ready_o {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_valid_o: coverpoint valid_o {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_ready_i: coverpoint ready_i {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_clr: coverpoint clr {
      bins active   = {1'b1};
      bins inactive = {1'b0};
    }
    // Fall-through: valid_i & ready_o & ready_i simultaneously (combinational pass)
    cx_fall_through: cross cp_valid_i, cp_ready_o, cp_ready_i;
    // Backpressure: fifo full (ready_o=0) while valid_o=1
    cx_backpressure: cross cp_ready_o, cp_valid_o {
      bins full_stall = binsof(cp_ready_o.deasserted) && binsof(cp_valid_o.asserted);
    }
    // Bug behavior: with fifo_v2 (no usage_o), valid_o and ready_o could glitch.
    // With fifo_v3, valid_o=1 implies ready_o=0 (depth=1) is proper backpressure.
    cx_valid_ready_states: cross cp_valid_o, cp_ready_o;
  endgroup

  cg_patch cg_inst = new();

  // Explicit sampling on clock edge
  always @(posedge clk) begin
    if (rst_n) cg_inst.sample();
  end

  // -------------------------------------------------------
  // Main test
  // -------------------------------------------------------
  initial begin
    // Init
    rst_n    = 1'b0;
    clr      = 1'b0;
    testmode = 1'b0;
    valid_i  = 1'b0;
    ready_i  = 1'b0;
    data_i   = '0;
    pass_count = 0;
    fail_count = 0;

    // Reset
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    // ---------------------------------------------------------
    // Test 1: Fall-through behavior (downstream ready, push data)
    //   When the FIFO is empty and downstream is ready, data
    //   should appear on data_o in the same cycle as valid_i.
    // ---------------------------------------------------------
    $display("[Test 1] Fall-through: data passes combinationally when downstream ready");
    ready_i = 1'b1;
    @(negedge clk);
    valid_i = 1'b1;
    data_i  = 16'hCAFE;
    @(negedge clk);
    // In fall-through mode with empty fifo and pop active, data passes through
    if (valid_o !== 1'b1) begin
      $display("FAIL: valid_o should be asserted during fall-through");
      fail_count++;
    end else begin
      pass_count++;
    end
    check_output(16'hCAFE);
    valid_i = 1'b0;
    @(posedge clk);
    @(negedge clk);

    // After removing input, output should go invalid (fifo empty, no push)
    if (valid_o !== 1'b0) begin
      $display("FAIL: valid_o should deassert when no data is present");
      fail_count++;
    end else begin
      pass_count++;
    end

    // ---------------------------------------------------------
    // Test 2: Backpressure - data stored when downstream not ready
    // ---------------------------------------------------------
    $display("[Test 2] Backpressure: data is stored when downstream is not ready");
    ready_i = 1'b0;
    @(negedge clk);
    valid_i = 1'b1;
    data_i  = 16'hBEEF;
    @(posedge clk);
    @(negedge clk);
    // Data should be stored in the FIFO (depth=1), valid_o asserted
    if (valid_o !== 1'b1) begin
      $display("FAIL: valid_o should be 1 when data stored in FIFO");
      fail_count++;
    end else begin
      pass_count++;
    end
    check_output(16'hBEEF);

    // FIFO full (depth=1), ready_o should deassert
    valid_i = 1'b0;
    @(posedge clk);
    @(negedge clk);
    if (ready_o !== 1'b0) begin
      $display("FAIL: ready_o should be 0 when FIFO is full");
      fail_count++;
    end else begin
      pass_count++;
    end

    // Now accept the data downstream
    ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    // After pop, FIFO should be empty
    if (valid_o !== 1'b0) begin
      $display("FAIL: valid_o should deassert after data is consumed");
      fail_count++;
    end else begin
      pass_count++;
    end
    if (ready_o !== 1'b1) begin
      $display("FAIL: ready_o should reassert after FIFO is drained");
      fail_count++;
    end else begin
      pass_count++;
    end

    // ---------------------------------------------------------
    // Test 3: Synchronous clear
    // ---------------------------------------------------------
    $display("[Test 3] Synchronous clear flushes stored data");
    ready_i = 1'b0;
    valid_i = 1'b1;
    data_i  = 16'hDEAD;
    @(posedge clk);
    @(negedge clk);
    valid_i = 1'b0;
    // Data stored, valid_o should be high
    if (valid_o !== 1'b1) begin
      $display("FAIL: valid_o should be 1 before clear");
      fail_count++;
    end else begin
      pass_count++;
    end

    // Assert clear for one cycle
    @(negedge clk);
    clr = 1'b1;
    @(posedge clk);  // flush takes effect on this edge
    @(negedge clk);
    clr = 1'b0;
    // After flush, FIFO should be empty
    if (valid_o !== 1'b0) begin
      $display("FAIL: valid_o should be 0 after synchronous clear");
      fail_count++;
    end else begin
      pass_count++;
    end
    if (ready_o !== 1'b1) begin
      $display("FAIL: ready_o should be 1 after synchronous clear");
      fail_count++;
    end else begin
      pass_count++;
    end

    // ---------------------------------------------------------
    // Test 4: Push while full should not overwrite
    // ---------------------------------------------------------
    $display("[Test 4] Push while full: second push is rejected");
    // Ensure FIFO is empty before test
    ready_i = 1'b1;
    repeat (3) @(posedge clk);
    ready_i = 1'b0;
    @(negedge clk);

    valid_i = 1'b1;
    data_i  = 16'h1111;
    @(posedge clk);
    @(negedge clk);
    valid_i = 1'b0;
    // FIFO has 0x1111
    @(posedge clk);
    @(negedge clk);

    // Try to push another value while full
    valid_i = 1'b1;
    data_i  = 16'h2222;
    @(posedge clk);
    @(negedge clk);
    valid_i = 1'b0;
    // Output should still show the first value
    check_output(16'h1111);

    // Drain
    ready_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    ready_i = 1'b0;
    @(posedge clk);
    @(negedge clk);

    // ---------------------------------------------------------
    // Test 5: Simultaneous push and pop (streaming)
    // ---------------------------------------------------------
    $display("[Test 5] Simultaneous push and pop (streaming)");
    // First fill the FIFO
    ready_i = 1'b0;
    valid_i = 1'b1;
    data_i  = 16'hA000;
    @(posedge clk);
    @(negedge clk);
    // Now push new data while also accepting output
    ready_i = 1'b1;
    valid_i = 1'b1;
    data_i  = 16'hA001;
    // Output should show the first value that was stored
    check_output(16'hA000);
    @(posedge clk);
    @(negedge clk);
    // Now the old data was popped and new data should be visible
    check_output(16'hA001);
    valid_i = 1'b0;
    @(posedge clk);
    @(negedge clk);
    ready_i = 1'b0;

    // ---------------------------------------------------------
    // Test 6: Random stimulus with scoreboard
    // ---------------------------------------------------------
    $display("[Test 6] Random push/pop with scoreboard (%0d transactions)", NUM_RANDOM_TXNS);
    // Drain first
    ready_i = 1'b1;
    repeat (3) @(posedge clk);
    ready_i = 1'b0;
    @(posedge clk);

    begin
      int txn_pushed;
      int txn_popped;
      data_t rand_data;

      txn_pushed = 0;
      txn_popped = 0;

      fork
        // Producer
        begin
          while (txn_pushed < NUM_RANDOM_TXNS) begin
            @(negedge clk);
            if ($urandom_range(0, 1)) begin
              valid_i = 1'b1;
              rand_data = $urandom;
              data_i = rand_data;
            end else begin
              valid_i = 1'b0;
            end
            @(posedge clk);
            #1;
            if (valid_i && ready_o) begin
              expected_queue.push_back(data_i);
              txn_pushed++;
            end
          end
          @(negedge clk);
          valid_i = 1'b0;
        end

        // Consumer
        begin
          while (txn_popped < NUM_RANDOM_TXNS) begin
            @(negedge clk);
            ready_i = ($urandom_range(0, 1)) ? 1'b1 : 1'b0;
            @(posedge clk);
            #1;
            if (valid_o && ready_i) begin
              if (expected_queue.size() == 0) begin
                $display("FAIL: Received data 0x%04h but expected queue is empty", data_o);
                fail_count++;
              end else begin
                data_t exp;
                exp = expected_queue.pop_front();
                if (data_o !== exp) begin
                  $display("FAIL: data_o = 0x%04h, expected 0x%04h (txn %0d)", data_o, exp, txn_popped);
                  fail_count++;
                end else begin
                  pass_count++;
                end
              end
              txn_popped++;
            end
          end
        end
      join

      // Drain any remaining
      ready_i = 1'b1;
      repeat (5) @(posedge clk);
      ready_i = 1'b0;
    end

    // ---------------------------------------------------------
    // Test 7: Reset clears state
    // ---------------------------------------------------------
    $display("[Test 7] Asynchronous reset clears state");
    ready_i = 1'b0;
    valid_i = 1'b1;
    data_i  = 16'hFFFF;
    @(posedge clk);
    @(negedge clk);
    valid_i = 1'b0;

    // Assert reset
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    @(negedge clk);
    if (valid_o !== 1'b0) begin
      $display("FAIL: valid_o should be 0 after reset");
      fail_count++;
    end else begin
      pass_count++;
    end
    if (ready_o !== 1'b1) begin
      $display("FAIL: ready_o should be 1 after reset");
      fail_count++;
    end else begin
      pass_count++;
    end

    // ---------------------------------------------------------
    // Summary
    // ---------------------------------------------------------
    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $display("========================================");
    $display("  Test Summary: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) begin
      $display("PASS: all fall_through_register (fifo_v3) tests passed.");
    end else begin
      $display("FAIL: %0d tests failed.", fail_count);
    end
    $finish;
  end

  // -------------------------------------------------------
  // Timeout watchdog
  // -------------------------------------------------------
  initial begin
    #100000;
    $display("FAIL: simulation timeout");
    $finish;
  end

  // -------------------------------------------------------
  // VCD dump
  // -------------------------------------------------------
  initial begin
    $dumpfile("tb_common_cells_fall_through_register_patch.vcd");
    $dumpvars(0);
  end

endmodule
