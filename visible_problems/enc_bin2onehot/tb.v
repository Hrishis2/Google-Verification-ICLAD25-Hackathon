`timescale 1ns / 1ps

module tb;

  // DUT Inputs
  reg           clk;
  reg           rst;
  reg           in_valid;
  reg   [3:0]   in;

  // DUT Output
  wire  [14:0]  out;
  
  // Testbench internal variables
  reg   [14:0]  expected_out;
  integer       i;
  integer       error_count = 0;

  // Instantiate the Device Under Test (DUT)
  enc_bin2onehot DUT (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in(in),
    .out(out)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Main test sequence
  initial begin
    // 1. Initialize and Reset
    rst = 1;
    in_valid = 0;
    in = 4'hX;
    #20;
    rst = 0;
    #10;
    
    // --- TEST 1: IN_VALID LOW ---
    // When in_valid is low, output must be all zeros, regardless of the 'in' value.
    // This checks for correct in_valid handling and potential combinational latch bugs.
    in_valid = 0;
    for (i = 0; i < 16; i = i + 1) begin
      in = i;
      #1; // Allow combinational logic to settle
      if (out !== 15'b0) begin
        $error("FAILED: When in_valid=0 and in=%d, out should be 15'b0, but was %b.", i, out);
        $finish;
      end
    end

    // --- TEST 2: CORE FUNCTIONALITY (VALID INPUTS) ---
    // When in_valid is high, iterate through all valid inputs (0-14).
    // This checks for correct decoding, off-by-one errors, decoding holes, and multi-hot errors.
    in_valid = 1;
    for (i = 0; i <= 14; i = i + 1) begin
      in = i;
      expected_out = 1'b1 << i;
      #1; // Settle time
      
      // Check 2a: Verify the output matches the expected one-hot value.
      if (out !== expected_out) begin
        $error("FAILED: Incorrect decoding for in=%d. Expected: %h, Got: %h", i, expected_out, out);
        $finish;
      end
      
      // Check 2b: Explicitly verify the output is truly one-hot.
      if ($countones(out) !== 1) begin
        $error("FAILED: Output is not one-hot for in=%d. Got: %b ($countones=%d)", i, out, $countones(out));
        $finish;
      end
    end

    // --- TEST 3: ILLEGAL INPUT (in = 15) ---
    // The spec says behavior is "undefined". A robust DUT should not alias this to a valid one-hot output.
    // An all-zero, multi-hot, or 'X' output is acceptable.
    in_valid = 1;
    in = 4'b1111;
    #1; // Settle time
    
    if ($countones(out) == 1) begin
      $error("FAILED: Illegal input in=15 produced a valid one-hot output: %b. This could indicate an aliasing bug.", out);
      $finish;
    end

    // --- TEST 4: CHECK FOR LATCH INFERENCE ---
    // Drive a valid output, then de-assert in_valid. The output must go to zero, not hold its state.
    // This also tests for accidental sequential logic.
    in_valid = 1;
    in = 4'hA; // 10
    #1;
    if (out !== (1'b1 << 10)) begin
      $error("FAILED (Setup for Latch Test): Incorrect decoding for in=10. Got: %b", out);
      $finish;
    end
    
    in_valid = 0; // De-assert valid
    #1;
    if (out !== 15'b0) begin
      $error("FAILED: Latch inferred! Output did not return to zero when in_valid was de-asserted. Got: %b", out);
      $finish;
    end
    
    // --- TEST 5: BACK-TO-BACK TRANSITIONS ---
    // Ensure the combinational logic settles correctly after rapid input changes.
    in_valid = 1;
    in = 4'h1; #1; if(out !== (1'b1 << 1))  $error("FAILED transition to 1");
    in = 4'hE; #1; if(out !== (1'b1 << 14)) $error("FAILED transition to 14");
    in = 4'h0; #1; if(out !== (1'b1 << 0))  $error("FAILED transition to 0");
    in = 4'h8; #1; if(out !== (1'b1 << 8))  $error("FAILED transition to 8");
    in = 4'hF; #1; // Back to illegal input
    in = 4'h7; #1; if(out !== (1'b1 << 7))  $error("FAILED transition from illegal to 7");

    // --- All tests completed successfully ---
    $display("TESTS PASSED");
    $finish;
  end

endmodule
