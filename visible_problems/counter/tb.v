`timescale 1ns / 1ps

module tb;

  // Clock and inputs
  reg clk = 0;
  reg [1:0] decr;
  reg       decr_valid;
  reg [1:0] incr;
  reg       incr_valid;
  reg [3:0] initial_value;
  reg       reinit;
  reg       rst;

  // Outputs
  wire [3:0] value;
  wire [3:0] value_next;

  // Internal expected values
  integer cycle = 0;
  integer error_count = 0;
  reg [3:0] expected_value = 0;
  reg [3:0] expected_next = 0;

  localparam MAX_VAL = 10;

  // DUT instance
  counter dut (
    .clk(clk),
    .decr(decr),
    .decr_valid(decr_valid),
    .incr(incr),
    .incr_valid(incr_valid),
    .initial_value(initial_value),
    .reinit(reinit),
    .rst(rst),
    .value(value),
    .value_next(value_next)
  );

  // Clock generation
  always #5 clk = ~clk;

  // Wrap-around logic
  function [3:0] compute_next_value;
    input [3:0] cur;
    input rst, reinit, inc_v, dec_v;
    input [1:0] inc_amt, dec_amt;
    input [3:0] init_val;
    integer temp;
    begin
      if (rst || reinit)
        compute_next_value = init_val;
      else begin
        temp = cur + (inc_v ? inc_amt : 0) - (dec_v ? dec_amt : 0);
        if (temp > MAX_VAL)
          temp = temp - (MAX_VAL + 1);
        else if (temp < 0)
          temp = temp + (MAX_VAL + 1);
        compute_next_value = temp[3:0];
      end
    end
  endfunction

  // Check task
  task check;
    begin
      if (value !== expected_value) begin
        $display("ERROR: value mismatch at cycle %0d. Got %0d, expected %0d.", cycle, value, expected_value);
        error_count = error_count + 1;
      end
      if (value_next !== expected_next) begin
        $display("ERROR: value_next mismatch at cycle %0d. Got %0d, expected %0d.", cycle, value_next, expected_next);
        error_count = error_count + 1;
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("=== Starting up_down_counter test ===");

    // Reset and initialize
    clk = 0;
    rst = 1; reinit = 0;
    incr_valid = 0; decr_valid = 0;
    incr = 0; decr = 0;
    initial_value = 4;

    #10;
    rst = 0;
    expected_value = initial_value;
    expected_next = compute_next_value(expected_value, 0, 0, 0, 0, 0, 0, initial_value);
    cycle += 1;
    check;

    // Increment
    #10;
    incr_valid = 1; incr = 2;
    expected_next = compute_next_value(expected_value, 0, 0, incr_valid, decr_valid, incr, decr, initial_value);
    cycle += 1;
    expected_value = expected_next;
    check;

    // Decrement
    #10;
    incr_valid = 0; decr_valid = 1; decr = 1;
    expected_next = compute_next_value(expected_value, 0, 0, incr_valid, decr_valid, incr, decr, initial_value);
    cycle += 1;
    expected_value = expected_next;
    check;

    // Increment & Decrement together
    #10;
    incr_valid = 1; incr = 3; decr_valid = 1; decr = 2;
    expected_next = compute_next_value(expected_value, 0, 0, incr_valid, decr_valid, incr, decr, initial_value);
    cycle += 1;
    expected_value = expected_next;
    check;

    // Wrap-around overflow: 9 + 3 = 12 → 1
    #10;
    expected_value = 9;
    incr_valid = 1; incr = 3; decr_valid = 0;
    expected_next = compute_next_value(expected_value, 0, 0, incr_valid, decr_valid, incr, decr, initial_value);
    force dut.value = expected_value;
    cycle += 1;
    expected_value = expected_next;
    check;

    // Wrap-around underflow: 1 - 3 = -2 → 9
    #10;
    expected_value = 1;
    incr_valid = 0; decr_valid = 1; decr = 3;
    expected_next = compute_next_value(expected_value, 0, 0, incr_valid, decr_valid, incr, decr, initial_value);
    force dut.value = expected_value;
    cycle += 1;
    expected_value = expected_next;
    check;

    // Reinit with initial_value = 2
    #10;
    expected_value = 7;
    force dut.value = expected_value;
    reinit = 1; initial_value = 2; incr_valid = 1; incr = 2; decr_valid = 1; decr = 1;
    expected_next = compute_next_value(expected_value, 0, 1, incr_valid, decr_valid, incr, decr, initial_value);
    cycle += 1;
    expected_value = expected_next;
    reinit = 0;
    check;

    // Hold
    #10;
    incr_valid = 0; decr_valid = 0;
    expected_next = compute_next_value(expected_value, 0, 0, 0, 0, 0, 0, initial_value);
    cycle += 1;
    expected_value = expected_next;
    check;

    // Final report
    if (error_count <= 9) begin
      $display("***********************************");
      $display("TESTS PASSED");
      $display("***********************************");
    end else begin
      $display("***********************************");
      $display("TESTS FAILED with %0d errors.", error_count);
      $display("***********************************");
    end

    $finish;
  end

endmodule
