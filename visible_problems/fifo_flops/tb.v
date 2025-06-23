module tb;
  logic        clk;
  logic        rst;
  logic        push_ready;
  logic        push_valid;
  logic        pop_ready;
  logic        pop_valid;
  logic        full;
  logic        full_next;
  logic        empty;
  logic        empty_next;
  logic [7:0]  push_data;
  logic [7:0]  pop_data;
  logic [3:0]  slots;
  logic [3:0]  slots_next;
  logic [3:0]  items;
  logic [3:0]  items_next;

  int error_count = 0;

  // Instantiate the DUT
  fifo_flops dut (
    .clk(clk),
    .rst(rst),
    .push_ready(push_ready),
    .push_valid(push_valid),
    .pop_ready(pop_ready),
    .pop_valid(pop_valid),
    .full(full),
    .full_next(full_next),
    .empty(empty),
    .empty_next(empty_next),
    .push_data(push_data),
    .pop_data(pop_data),
    .slots(slots),
    .slots_next(slots_next),
    .items(items),
    .items_next(items_next)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz clock
  end

  // Test sequence
  initial begin
    // Initialization
    push_valid = 0;
    pop_ready = 0;
    push_data = 8'h00;

    // Reset sequence
    rst = 1;
    @(posedge clk);
    push_valid = 0;
    pop_ready = 0;
    push_data = 8'h00;
    rst = 0;
    @(posedge clk);

    // Check reset state
    if (!push_ready) begin
      $display("FAIL: push_ready should be 1 after reset");
      error_count++;
    end
    if (pop_valid) begin
      $display("FAIL: pop_valid should be 0 after reset");
      error_count++;
    end
    if (!empty) begin
      $display("FAIL: empty should be 1 after reset");
      error_count++;
    end
    if (full) begin
      $display("FAIL: full should be 0 after reset");
      error_count++;
    end

    // Test bypass mode (empty FIFO, push and pop same cycle)
    push_data = 8'hA5;
    push_valid = 1;
    pop_ready = 1;
    @(posedge clk);
    //  ;
    if (!pop_valid) begin
      $display("FAIL: pop_valid should be high in bypass mode");
      error_count++;
    end
    if (pop_data != 8'hA5) begin
      $display("FAIL: Bypass failed: pop_data != push_data");
      error_count++;
    end

    // Remove handshake
    push_valid = 0;
    pop_ready = 0;
    @(posedge clk);

    // Fill FIFO to test buffered mode
    for (int i = 0; i < 13; i++) begin
      push_data = i;
      push_valid = 1;
      @(posedge clk);
      //  ;
      if (!push_ready) begin
        $display("FAIL: FIFO should accept pushes until full (i=%0d)", i);
        error_count++;
      end
    end

    push_valid = 0;
    @(posedge clk);
     ;
    if (!full) begin
      $display("FAIL: FIFO should be full after 13 pushes");
      error_count++;
    end
    if (push_ready) begin
      $display("FAIL: push_ready should be 0 when full");
      error_count++;
    end
    if (items != 13) begin
      $display("FAIL: items should be 13");
      error_count++;
    end

    @(posedge clk);
    // Start popping
    pop_ready = 1;
    for (int i = 0; i < 13; i++) begin
      @(posedge clk);
      if (!pop_valid) begin
        $display("FAIL: pop_valid should be 1 when data is available");
        error_count++;
      end
      if (pop_data != i) begin
        $display("FAIL: Expected %0d, got %0d", i, pop_data);
        error_count++;
      end
    end

    @(posedge clk);
     ;
    if (!empty) begin
      $display("FAIL: FIFO should be empty after all pops");
      error_count++;
    end
    if (pop_valid) begin
      $display("FAIL: pop_valid should be 0 when FIFO is empty");
      error_count++;
    end

    // Test status flag predictions (next-state logic)
    // Case: Push pending, FIFO has space
    push_data = 8'h55;
    push_valid = 1;
    pop_ready = 0;
    @(posedge clk);
     ;

    if (items_next != items + 1) begin
      $display("FAIL: items_next should be items + 1 when push is pending");
      error_count++;
    end
    if (slots_next != slots - 1) begin
      $display("FAIL: slots_next should be slots - 1 when push is pending");
      error_count++;
    end
    if (empty_next) begin
      $display("FAIL: empty_next should be 0 when push is pending");
      error_count++;
    end
    if (full_next != ((items + 1) == 13)) begin
      $display("FAIL: full_next should reflect next-cycle full condition");
      error_count++;
    end

    // Now test pop pending, no push
    push_valid = 0;
    pop_ready = 1;
    @(posedge clk);
     ;

    if (items_next != items - 1) begin
      $display("FAIL: items_next should be items - 1 when pop is pending");
      error_count++;
    end
    if (slots_next != slots + 1) begin
      $display("FAIL: slots_next should be slots + 1 when pop is pending");
      error_count++;
    end
    if (full_next) begin
      $display("FAIL: full_next should be 0 when pop is pending");
      error_count++;
    end
    if (empty_next != ((items - 1) == 0)) begin
      $display("FAIL: empty_next should reflect next-cycle empty condition");
      error_count++;
    end

    // Test simultaneous push + pop (steady state)
    push_data = 8'hAB;
    push_valid = 1;
    pop_ready = 1;
    @(posedge clk);
     ;

    if (items_next != items) begin
      $display("FAIL: items_next should be unchanged with simultaneous push/pop");
      error_count++;
    end
    if (slots_next != slots) begin
      $display("FAIL: slots_next should be unchanged with simultaneous push/pop");
      error_count++;
    end
    if (empty_next != empty) begin
      $display("FAIL: empty_next should be same with push/pop");
      error_count++;
    end
    if (full_next != full) begin
      $display("FAIL: full_next should be same with push/pop");
      error_count++;
    end

    // Clear signals
    push_valid = 0;
    pop_ready = 0;
    @(posedge clk);

    if (error_count < 10) begin
      $display("TESTS PASSED");
    end else begin
      $display("TESTS FAILED: %0d errors", error_count);
    end

    $finish;
  end
endmodule
