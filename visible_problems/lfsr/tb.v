`timescale 1ns / 1ps

module tb;

  // DUT Inputs
  reg        clk;
  reg        rst;
  reg        reinit;
  reg        advance;
  reg [4:0]  initial_state;
  reg [4:0]  taps;

  // DUT Outputs
  wire        out;
  wire [4:0] out_state;
  
  // Testbench internal variables
  integer    error_count;
  reg [4:0]  expected_state_model;

  // Instantiate the Device Under Test (DUT)
  lfsr dut (
    .clk(clk),
    .rst(rst),
    .reinit(reinit),
    .advance(advance),
    .out(out),
    .initial_state(initial_state),
    .taps(taps),
    .out_state(out_state)
  );

  // Clock Generator
  always #5 clk = ~clk;

  // Task to check the LFSR state and report errors
  task check_state(input [4:0] expected_val, input string message);
    if (out_state !== expected_val) begin
      $display("@%0t: ERROR: %s. Expected state: 5'b%b, Got: 5'b%b", $time, message, expected_val, out_state);
      error_count = error_count + 1;
    end
  endtask

  // Task to check the single-bit output 'out'
  task check_out_bit;
      if (out !== out_state[0]) begin
          $display("@%0t: ERROR: 'out' signal mismatch. Expected out_state[0] (%b), Got %b.", $time, out_state[0], out);
          error_count = error_count + 1;
      end
  endtask

  // Main test sequence
  initial begin
    // Testbench local variables
    reg feedback_bit;
    
    // ----------------------------------------------------------------
    // Initialization
    // ----------------------------------------------------------------
    clk = 0;
    rst = 0;
    reinit = 0;
    advance = 0;
    initial_state = 5'b0;
    taps = 5'b0;
    error_count = 0;
    #10;

    // ----------------------------------------------------------------
    // TEST 1: Synchronous Reset and State Hold
    // Verifies synchronous reset and that the state holds when no control signal is active.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 1: Synchronous Reset and State Hold");
    @(posedge clk);
    rst <= 1;
    initial_state <= 5'b11010;
    
    @(posedge clk);
    // On this edge, state should be loaded from initial_state.
    rst <= 0;
    initial_state <= 5'bx; // Ensure DUT is not using the live input
    check_state(5'b11010, "State after synchronous reset");
    check_out_bit();
    
    @(posedge clk);
    // State should hold since rst, reinit, and advance are low.
    check_state(5'b11010, "State hold after reset");
    check_out_bit();
    #10;

    // ----------------------------------------------------------------
    // TEST 2: Core LFSR Advancement
    // Verifies the feedback calculation and shift operation for a maximal-length sequence.
    // Taps = 5'b10100 corresponds to polynomial x^5 + x^2 + 1.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 2: Core LFSR Advancement");
    taps <= 5'b10100;
    advance <= 1;
    expected_state_model = 5'b11010;

    // Run for a full cycle (2^5 - 1 = 31 states) plus a few more to check rollover.
    for (integer i = 0; i < 35; i = i + 1) begin
      @(posedge clk);
      feedback_bit = ^(expected_state_model & taps);
      expected_state_model = {expected_state_model[3:0], feedback_bit};
      check_state(expected_state_model, $sformatf("Advancement cycle %0d", i+1));
      check_out_bit();
    end
    advance <= 0;
    #10;

    // ----------------------------------------------------------------
    // TEST 3: Reinitialization
    // Verifies the `reinit` signal correctly loads `initial_state`.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 3: Reinitialization");
    @(posedge clk);
    reinit <= 1;
    initial_state <= 5'b01011;

    @(posedge clk);
    // On this edge, state should be reinitialized.
    reinit <= 0;
    initial_state <= 5'bx;
    check_state(5'b01011, "State after reinit");
    check_out_bit();
    
    @(posedge clk);
    // State should hold after reinit.
    check_state(5'b01011, "State hold after reinit");
    check_out_bit();
    #10;
    
    // ----------------------------------------------------------------
    // TEST 4: Control Priority (rst > reinit > advance)
    // Verifies that reset has the highest priority, followed by reinit.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 4: Control Priority");
    // Test reinit over advance
    @(posedge clk);
    reinit <= 1;
    advance <= 1;
    initial_state <= 5'b11100;
    
    @(posedge clk);
    // State should reinitialize, not advance.
    check_state(5'b11100, "Priority: reinit over advance");
    
    // Test rst over reinit and advance
    rst <= 1;
    initial_state <= 5'b10001;

    @(posedge clk);
    // State should reset, ignoring reinit and advance.
    rst <= 0;
    reinit <= 0;
    advance <= 0;
    check_state(5'b10001, "Priority: rst over reinit & advance");
    #10;
    
    // ----------------------------------------------------------------
    // TEST 5: Stuck-at-Zero State
    // An LFSR with initial state 0 should never leave state 0.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 5: Stuck-at-Zero State");
    @(posedge clk);
    rst <= 1;
    initial_state <= 5'b00000;
    
    @(posedge clk);
    rst <= 0;
    check_state(5'b00000, "Reset to zero state");
    
    advance <= 1;
    @(posedge clk);
    // Feedback from all-zero state is always 0.
    check_state(5'b00000, "Stuck-at-zero check (cycle 1)");
    
    @(posedge clk);
    check_state(5'b00000, "Stuck-at-zero check (cycle 2)");
    advance <= 0;
    #10;
    
    // ----------------------------------------------------------------
    // TEST 6: Dynamic Tap Change
    // Verifies the LFSR uses the current `taps` input, not a latched version.
    // ----------------------------------------------------------------
    $display("INFO: Starting Test 6: Dynamic Tap Change");
    // Start from a known state with original taps
    reinit <= 1;
    initial_state <= 5'b10000;
    taps <= 5'b10100; // Original taps
    @(posedge clk);
    reinit <= 0;
    
    // Calculate next state with original taps
    // expected = {0000, ^(10000 & 10100)} = {0000, ^(10000)} = 5'b00001
    advance <= 1;
    @(posedge clk);
    check_state(5'b00001, "State after one advance with original taps");
    
    // Now, change the taps. The current state is 5'b00001.
    taps <= 5'b11000; // New taps (x^5 + x^4 + 1)
    
    // Calculate next state with NEW taps
    // expected = {0001, ^(00001 & 11000)} = {0001, ^(00000)} = 5'b00010
    @(posedge clk);
    check_state(5'b00010, "State after dynamic tap change");
    advance <= 0;
    #10;

    // ----------------------------------------------------------------
    // Final Results
    // ----------------------------------------------------------------
    if (error_count == 0) begin
      $display("TESTS PASSED");
    end else begin
      $display("TESTS FAILED with %0d errors.", error_count);
    end
    $finish;
  end

endmodule
