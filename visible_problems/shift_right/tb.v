`timescale 1ns / 1ps

module tb;

  // DUT instance signals
  reg  [95:0] in;
  reg  [2:0]  shift;
  reg  [11:0] fill;
  wire [95:0] out;
  wire        out_valid;

  // Testbench internal variables
  reg [95:0] expected_out;
  integer      i, s;

  // Instantiate the Device Under Test (DUT)
  shift_left dut (
    .out_valid(out_valid),
    .in(in),
    .shift(shift),
    .fill(fill),
    .out(out)
  );

  // Verification task
  task check;
    input [95:0] local_expected_out;
    input        is_valid_case;
  begin
    #1; // Allow combinational logic to settle

    if (is_valid_case) begin
      // For valid shifts, check both 'out' and 'out_valid'
      if (out_valid !== 1'b1 || out !== local_expected_out) begin
        $display("ERROR: Test failed for valid shift amount.");
        $display("  Time: %0t", $time);
        $display("  Inputs: shift = %d, fill = %h", shift, fill);
        $display("          in      = %h", in);
        $display("  Expected: out_valid = 1, out = %h", local_expected_out);
        $display("  Actual:   out_valid = %b, out = %h", out_valid, out);
        $error(1, "Mismatch detected.");
      end
    end else begin
      // For invalid shifts, only 'out_valid' is checked
      if (out_valid !== 1'b0) begin
        $display("ERROR: Test failed for invalid shift amount.");
        $display("  Time: %0t", $time);
        $display("  Inputs: shift = %d", shift);
        $display("  Expected: out_valid = 0");
        $display("  Actual:   out_valid = %b", out_valid);
        $error(1, "Mismatch detected.");
      end
    end
  end
  endtask

  initial begin
    // --- Test Plan ---
    // 1. Directed test for all valid shift amounts (0-5) with a patterned input.
    // 2. Directed test for all invalid shift amounts (6-7).
    // 3. Randomized test covering various inputs, fills, and valid shift amounts.

    $display("Starting verification of shift_left module...");

    // --- Test Case 1: Valid Shifts (Directed) ---
    in = {12'h777, 12'h666, 12'h555, 12'h444, 12'h333, 12'h222, 12'h111, 12'h000};
    fill = 12'hAAA;

    for (s = 0; s <= 5; s = s + 1) begin
      shift = s;
      // Calculate expected output
      for (i = 0; i < 8; i = i + 1) begin
        if (i < s) begin
          expected_out[12*i +: 12] = fill;
        end else begin
          expected_out[12*i +: 12] = in[12*(i-s) +: 12];
        end
      end
      check(expected_out, 1'b1);
    end

    // --- Test Case 2: Invalid Shifts (Directed) ---
    for (s = 6; s <= 7; s = s + 1) begin
      shift = s;
      check(0, 1'b0); // Expected output is don't care, pass dummy value
    end

    // --- Test Case 3: Randomized Tests ---
    repeat (50) begin
      in = {$urandom(), $urandom(), $urandom()};
      fill = $urandom();
      shift = $urandom_range(0, 5); // Only test valid shifts randomly

      for (i = 0; i < 8; i = i + 1) begin
        if (i < shift) begin
          expected_out[12*i +: 12] = fill;
        end else begin
          expected_out[12*i +: 12] = in[12*(i-shift) +: 12];
        end
      end
      check(expected_out, 1'b1);
    end

    $display("TESTS PASSED");
    $finish;
  end

endmodule
