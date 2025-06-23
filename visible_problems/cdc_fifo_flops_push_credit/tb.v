`timescale 1ns/1ps

module tb;

  // Parameters
  localparam FIFO_DEPTH = 17;
  localparam DATA_WIDTH = 8;
  localparam PTR_WIDTH = 5; // ceil(log2(FIFO_DEPTH)) = 5

  // Clock and Reset Signals
  reg push_clk;
  reg pop_clk;
  reg push_rst;
  reg pop_rst;

  // DUT Inputs
  reg               push_sender_in_reset;
  reg               push_credit_stall;
  reg               push_valid;
  reg               pop_ready;
  reg [DATA_WIDTH-1:0] push_data;
  reg [PTR_WIDTH-1:0]  credit_initial_push;
  reg [PTR_WIDTH-1:0]  credit_withhold_push;

  // DUT Outputs
  wire              push_receiver_in_reset;
  wire              push_credit;
  wire              pop_valid;
  wire              push_full;
  wire              pop_empty;
  wire [DATA_WIDTH-1:0] pop_data;
  wire [PTR_WIDTH-1:0]  push_slots;
  wire [PTR_WIDTH-1:0]  credit_count_push;
  wire [PTR_WIDTH-1:0]  credit_available_push;
  wire [PTR_WIDTH-1:0]  pop_items;

  // Testbench internal variables
  logic [DATA_WIDTH-1:0] scoreboard_q[$];
  logic [PTR_WIDTH-1:0]  expected_credits;
  integer                errors = 0;
  integer                i;

  // Instantiate the DUT
  cdc_fifo_flops_push_credit dut (
      .push_clk(push_clk),
      .push_rst(push_rst),
      .pop_clk(pop_clk),
      .pop_rst(pop_rst),
      .push_sender_in_reset(push_sender_in_reset),
      .push_receiver_in_reset(push_receiver_in_reset),
      .push_credit_stall(push_credit_stall),
      .push_credit(push_credit),
      .push_valid(push_valid),
      .pop_ready(pop_ready),
      .pop_valid(pop_valid),
      .push_full(push_full),
      .pop_empty(pop_empty),
      .push_data(push_data),
      .pop_data(pop_data),
      .push_slots(push_slots),
      .credit_initial_push(credit_initial_push),
      .credit_withhold_push(credit_withhold_push),
      .credit_count_push(credit_count_push),
      .credit_available_push(credit_available_push),
      .pop_items(pop_items)
  );

  // Clock generators
  initial begin
    push_clk = 0;
    forever #5 push_clk = ~push_clk; // 100 MHz
  end

  initial begin
    pop_clk = 0;
    forever #7 pop_clk = ~pop_clk; // ~71.4 MHz
  end

  // Monitor for data integrity and scoreboard update
  always @(posedge pop_clk) begin
    if (pop_valid && pop_ready) begin
      if (scoreboard_q.size() == 0) begin
        $display("[%0t] ERROR: Pop occurred from an empty DUT, but scoreboard was empty.", $time);
        errors = errors + 1;
      end else begin
        logic [DATA_WIDTH-1:0] expected_data;
        expected_data = scoreboard_q.pop_front();
        if (pop_data !== expected_data) begin
          $display("[%0t] ERROR: Data mismatch! Expected: 0x%h, Got: 0x%h", $time, expected_data, pop_data);
          errors = errors + 1;
        end
      end
    end
  end
  
  // Monitor for credit return
  always @(posedge push_clk) begin
      if (push_credit) begin
          if (expected_credits < FIFO_DEPTH)
            expected_credits <= expected_credits + 1;
      end
  end

  // Test sequence
  initial begin
    $display("---------- Starting Testbench ----------");
    initialize_signals();

    // --- TEST 1: Synchronous Reset and Initialization ---
    $display("[%0t] TEST 1: Synchronous Reset and Initialization", $time);
    apply_both_resets(FIFO_DEPTH, 0);
    check_initial_state(FIFO_DEPTH, 0);
    release_both_resets();
    @(posedge push_clk);
    @(posedge pop_clk);
    check_initial_state(FIFO_DEPTH, 0);

    // --- TEST 2: Push-side Reset Handshake ---
    $display("[%0t] TEST 2: Push-side Reset Handshake", $time);
    push_sender_in_reset = 1;
    @(posedge push_clk);
    if (push_receiver_in_reset !== 1) begin
      $display("[%0t] ERROR: push_receiver_in_reset should be high when push_sender_in_reset is high.", $time);
      errors = errors + 1;
    end
    push_item(8'hA1); // This push should be ignored
    @(posedge push_clk);
    if (pop_items !== 0) begin
      $display("[%0t] ERROR: FIFO accepted data while in sender reset.", $time);
      errors = errors + 1;
    end
    push_sender_in_reset = 0;
    @(posedge push_clk); @(posedge push_clk);
    if (push_receiver_in_reset !== 0) begin
      $display("[%0t] ERROR: push_receiver_in_reset should go low after sender reset is deasserted.", $time);
      errors = errors + 1;
    end

    // --- TEST 3: Basic Fill and Empty ---
    $display("[%0t] TEST 3: Basic Fill and Empty", $time);
    apply_both_resets(FIFO_DEPTH, 0);
    release_both_resets();
    
    // Fill half the FIFO
    for (i = 0; i < 8; i = i + 1) begin
        push_item(i);
    end
    wait_for_sync(5);
    if (pop_items !== 8) begin
        $display("[%0t] ERROR: pop_items should be 8, but is %d", $time, pop_items);
        errors = errors + 1;
    end
    
    // Empty it
    for (i = 0; i < 8; i = i + 1) begin
        pop_item();
    end
    wait_for_sync(5);
     if (pop_items !== 0 || !pop_empty) begin
        $display("[%0t] ERROR: FIFO should be empty. pop_items=%d, pop_empty=%b", $time, pop_items, pop_empty);
        errors = errors + 1;
    end
    if (scoreboard_q.size() !== 0) begin
        $display("[%0t] ERROR: Scoreboard should be empty but has %d items.", $time, scoreboard_q.size());
        errors = errors + 1;
    end

    // --- TEST 4: Full Condition and Write-While-Full ---
    $display("[%0t] TEST 4: Full Condition Test", $time);
    apply_both_resets(FIFO_DEPTH, 0);
    release_both_resets();
    for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
        push_item(i);
    end
    wait_for_sync(5);
    if (!push_full) begin
        $display("[%0t] ERROR: push_full should be asserted when FIFO has %d items.", $time, FIFO_DEPTH);
        errors = errors + 1;
    end
    if (push_slots !== 0) begin
        $display("[%0t] ERROR: push_slots should be 0 when full, but is %d.", $time, push_slots);
        errors = errors + 1;
    end
    
    push_item(8'hFF); // Attempt to overflow
    wait_for_sync(5);
    if (pop_items !== FIFO_DEPTH) begin
        $display("[%0t] ERROR: FIFO overflowed! pop_items should be %d, but is %d.", $time, FIFO_DEPTH, pop_items);
        errors = errors + 1;
    end

    // Pop one item and check full flag
    pop_item();
    wait_for_sync(5);
    if (push_full) begin
        $display("[%0t] ERROR: push_full should deassert after one item is popped.", $time);
        errors = errors + 1;
    end
    
    // --- TEST 5: Pop Ready Handshake Stalling ---
    $display("[%0t] TEST 5: Pop Ready Stalling", $time);
    pop_ready = 0;
    wait_for_sync(10);
    logic [DATA_WIDTH-1:0] stalled_data = pop_data;
    if (pop_items !== (FIFO_DEPTH - 1)) begin
        $display("[%0t] ERROR: pop_items changed while pop_ready was low. Expected %d, got %d", $time, FIFO_DEPTH-1, pop_items);
        errors = errors + 1;
    end
    wait_for_sync(10);
    if (stalled_data !== pop_data) begin
        $display("[%0t] ERROR: pop_data changed while stalled.", $time);
        errors = errors + 1;
    end
    pop_ready = 1;
    @(posedge pop_clk); // Pop completes

    // --- TEST 6: Credit Stall and Withholding ---
    $display("[%0t] TEST 6: Credit Stall and Withholding", $time);
    apply_both_resets(FIFO_DEPTH, 5); // Withhold 5 credits
    release_both_resets();
    wait_for_sync(5);
    if (credit_available_push !== (FIFO_DEPTH - 5)) begin
        $display("[%0t] ERROR: Credit withholding failed. Expected %d, got %d", $time, FIFO_DEPTH-5, credit_available_push);
        errors = errors + 1;
    end
    
    // Fill up to the withheld limit
    for (i = 0; i < (FIFO_DEPTH - 5); i = i + 1) begin
        push_item(i);
    end
    wait_for_sync(5);
    if(!push_full) begin
        $display("[%0t] ERROR: FIFO should be full due to credit withholding.", $time);
        errors = errors + 1;
    end
    
    // Stall credits while popping
    push_credit_stall = 1;
    pop_item();
    pop_item();
    wait_for_sync(5);
    if (credit_available_push !== (FIFO_DEPTH - 5)) begin
        $display("[%0t] ERROR: Credits should not be returned while stalled. Expected %d, got %d", $time, FIFO_DEPTH-5, credit_available_push);
        errors = errors + 1;
    end
    
    push_credit_stall = 0;
    wait_for_sync(10); // Wait for credits to sync
    if (credit_available_push !== (FIFO_DEPTH - 5 + 2)) begin
        $display("[%0t] ERROR: Credits not returned after stall released. Expected %d, got %d", $time, FIFO_DEPTH-5+2, credit_available_push);
        errors = errors + 1;
    end

    // --- TEST 7: Asynchronous Reset Domains ---
    $display("[%0t] TEST 7: Asynchronous Reset", $time);
    apply_both_resets(FIFO_DEPTH, 0);
    release_both_resets();
    for(i=0; i<10; i=i+1) push_item(i);
    wait_for_sync(5);
    
    // Reset only push domain
    push_rst = 1;
    @(posedge push_clk); @(posedge push_clk); @(posedge push_clk);
    push_rst = 0;
    
    // After push reset, pointers might be misaligned. A robust fifo should recover.
    // We expect the push side to reset its view, thinking it's empty, while pop side still has items.
    wait_for_sync(5);
    if(credit_available_push !== FIFO_DEPTH) begin
        $display("[%0t] ERROR: Push side available credits didn't reset correctly. Expected %d, got %d.", $time, FIFO_DEPTH, credit_available_push);
        errors = errors + 1;
    end
    if(pop_items === 0) begin
        $display("[%0t] ERROR: Pop side should retain items after only push side reset.", $time);
        errors = errors + 1;
    end
    
    // Now empty the FIFO fully to see if it recovers
    pop_ready = 1;
    repeat(15) @(posedge pop_clk);
    wait_for_sync(5);
    if(pop_items !== 0) begin
        $display("[%0t] ERROR: FIFO did not empty correctly after push-only reset.", $time);
        errors = errors + 1;
    end
    
    // --- TEST 8: Randomized Stress Test ---
    $display("[%0t] TEST 8: Randomized Stress Test", $time);
    apply_both_resets(FIFO_DEPTH, 0);
    release_both_resets();
    pop_ready = 0;
    
    fork
        // Pusher process
        begin
            repeat (200) begin
                if (!push_full && $random % 2) begin
                    push_item($random);
                end else begin
                    @(posedge push_clk);
                end
            end
        end
        // Popper process
        begin
            repeat (200) begin
                if ($random % 3) begin // Pop more often than not
                    pop_ready <= 1;
                end else begin
                    pop_ready <= 0;
                end
                @(posedge pop_clk);
            end
            pop_ready <= 1; // Ensure we drain at the end
        end
    join
    
    // Drain any remaining items
    wait_for_sync(5);
    while (scoreboard_q.size() > 0) begin
        pop_item();
    end
    wait_for_sync(10);
    
    if (pop_items !== 0 || !pop_empty) begin
        $display("[%0t] ERROR: Stress test failed, FIFO not empty at end. items=%d, empty=%b", $time, pop_items, pop_empty);
        errors = errors + 1;
    end
    if (scoreboard_q.size() !== 0) begin
        $display("[%0t] ERROR: Stress test failed, scoreboard not empty at end.", $time);
        errors = errors + 1;
    end

    // --- TEST 9: Delayed Reset Vulnerability ---
    $display("[%0t] TEST 9: Delayed Reset Vulnerability Test", $time);
    initialize_signals();
    push_rst = 1;
    push_valid = 1;
    push_data = 8'hDE;
    @(posedge push_clk);
    push_rst = 0;
    push_valid = 0;
    @(posedge push_clk); @(posedge push_clk);
    if (!pop_empty) begin
        $display("[%0t] ERROR: Spurious write occurred during reset assertion cycle.", $time);
        errors = errors + 1;
    end

    // --- FINAL CHECK ---
    if (errors == 0) begin
      $display("---------- TESTS PASSED ----------");
    end else begin
      $display("---------- TESTS FAILED: %0d errors ----------", errors);
    end
    $finish;
  end

  // --- TASKS ---
  task initialize_signals;
    push_rst = 1;
    pop_rst = 1;
    push_sender_in_reset = 0;
    push_credit_stall = 0;
    push_valid = 0;
    pop_ready = 0;
    push_data = 0;
    credit_initial_push = 0;
    credit_withhold_push = 0;
    scoreboard_q.delete();
    expected_credits = 0;
  endtask

  task apply_both_resets(input [PTR_WIDTH-1:0] initial_val, input [PTR_WIDTH-1:0] withhold_val);
    initialize_signals();
    push_rst = 1;
    pop_rst = 1;
    credit_initial_push = initial_val;
    credit_withhold_push = withhold_val;
    expected_credits = initial_val - withhold_val;
    @(posedge push_clk);
    @(posedge pop_clk);
  endtask

  task release_both_resets;
    push_rst = 0;
    pop_rst = 0;
    @(posedge push_clk);
    @(posedge pop_clk);
    pop_ready = 1; // Default to ready after reset
  endtask
  
  task check_initial_state(input [PTR_WIDTH-1:0] initial_val, input [PTR_WIDTH-1:0] withhold_val);
    wait_for_sync(5);
    if (!pop_empty)           begin $display("[%0t] ERROR: pop_empty not 1 on reset.", $time); errors = errors + 1; end
    if (push_full)            begin $display("[%0t] ERROR: push_full not 0 on reset.", $time); errors = errors + 1; end
    if (pop_items !== 0)      begin $display("[%0t] ERROR: pop_items not 0 on reset.", $time); errors = errors + 1; end
    if (credit_initial_push !== initial_val) begin $display("[%0t] ERROR: credit_initial_push is incorrect.", $time); errors = errors + 1; end
    if (credit_count_push !== initial_val) begin $display("[%0t] ERROR: credit_count_push not initialized.", $time); errors = errors + 1; end
    if (credit_available_push !== (initial_val - withhold_val)) begin $display("[%0t] ERROR: credit_available_push not initialized correctly.", $time); errors = errors + 1; end
  endtask

  task push_item(input [DATA_WIDTH-1:0] data);
    @(posedge push_clk);
    if (push_full) begin
        // Wait until not full, or timeout
        wait(!push_full) @(posedge push_clk);
    end
    push_valid <= 1;
    push_data <= data;
    scoreboard_q.push_back(data);
    expected_credits <= expected_credits - 1;
    @(posedge push_clk);
    push_valid <= 0;
  endtask

  task pop_item;
    @(posedge pop_clk);
    if (!pop_valid) begin
        // Wait until valid, or timeout
        wait(pop_valid) @(posedge pop_clk);
    end
    pop_ready <= 1;
    @(posedge pop_clk);
    pop_ready <= 0; // Default to not ready for next transaction
  endtask
  
  task wait_for_sync(input integer cycles);
      repeat(cycles) @(posedge push_clk);
      repeat(cycles) @(posedge pop_clk);
  endtask

endmodule
