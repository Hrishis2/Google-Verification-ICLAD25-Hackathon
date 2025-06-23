`timescale 1ns / 1ps

module tb;

    // Parameters
    localparam DATA_WIDTH     = 12;
    localparam CODEWORD_WIDTH = 13;
    localparam CLK_PERIOD     = 10;

    // Testbench Signals
    reg                          clk;
    reg                          rst;
    reg                          data_valid;
    reg  [DATA_WIDTH-1:0]        data;
    wire                         enc_valid;
    wire [CODEWORD_WIDTH-1:0]    enc_codeword;

    integer error_count = 0;

    // DUT Instantiation
    ecc_sed_encoder dut (
        .clk          (clk),
        .rst          (rst),
        .data_valid   (data_valid),
        .data         (data),
        .enc_valid    (enc_valid),
        .enc_codeword (enc_codeword)
    );

    // Clock Generator
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Task to apply a test vector and check the result
    task apply_and_check;
        input [DATA_WIDTH-1:0] test_data;
        input string           test_name;
    begin
        logic expected_parity;
        logic [CODEWORD_WIDTH-1:0] expected_codeword;

        // Apply stimulus
        data_valid = 1'b1;
        data = test_data;
        #1; // Allow combinational logic to settle (tests for latency)

        // Calculate expected values
        expected_parity = ^test_data; // XOR reduction for even parity
        expected_codeword = {expected_parity, test_data};

        // Check 1: enc_valid should be high when data_valid is high
        if (enc_valid !== 1'b1) begin
            $error("[%s] FAIL: enc_valid is %b, expected 1'b1.", test_name, enc_valid);
            error_count++;
        end

        // Check 2: The encoded codeword must match the expected value
        if (enc_codeword !== expected_codeword) begin
            $error("[%s] FAIL: Codeword mismatch.\n\tData:     %h\n\tExpected: %b\n\tActual:   %b",
                   test_name, test_data, expected_codeword, enc_codeword);
            error_count++;
        end

        // Check 3: Redundant check to confirm even parity property
        if (^enc_codeword !== 1'b0) begin
            $error("[%s] FAIL: Codeword does not have even parity. XOR reduction of output is %b.", test_name, ^enc_codeword);
            error_count++;
        end

        // De-assert valid to test the follow-through behavior
        data_valid = 1'b0;
        #1;
        if (enc_valid !== 1'b0) begin
            $error("[%s] FAIL: enc_valid failed to de-assert. Is %b, expected 1'b0.", test_name, enc_valid);
            error_count++;
        end

        @(posedge clk); // Synchronize to the clock for the next test
    end
    endtask

    // Main Test Sequence
    initial begin
        logic [CODEWORD_WIDTH-1:0] codeword_before_reset;

        // 1. Initialization and Reset Test
        rst = 1'b1;
        data_valid = 1'b0;
        data = 'x;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // 2. Core Functionality Tests
        apply_and_check(12'h000, "All Zeros Data");
        apply_and_check(12'hFFF, "All Ones Data");
        apply_and_check(12'h555, "Alternating 01s");
        apply_and_check(12'hAAA, "Alternating 10s");
        apply_and_check(12'hC3A, "Random Pattern 1");
        apply_and_check(12'h9F1, "Random Pattern 2");

        // 3. Edge Case: Walking '1' Test (checks all bits are included in parity)
        for (int i = 0; i < DATA_WIDTH; i++) begin
            apply_and_check(1'b1 << i, $sformatf("Walking One, Bit %0d", i));
        end

        // 4. Edge Case: Walking '0' Test
        for (int i = 0; i < DATA_WIDTH; i++) begin
            apply_and_check(~(1'b1 << i), $sformatf("Walking Zero, Bit %0d", i));
        end

        // 5. Randomized Tests
        for (int i = 0; i < 200; i++) begin
            apply_and_check($random, $sformatf("Random Test #%0d", i));
        end

        // 6. Test for incorrect reset influence on combinational logic
        data_valid = 1'b1;
        data = 12'hCBA;
        #1; // Settle
        codeword_before_reset = enc_codeword;
        rst = 1'b1; // Assert reset
        #1; // Settle again
        if (enc_codeword !== codeword_before_reset) begin
            $error("[Reset Influence Test] FAIL: Reset must not affect combinational output when data is valid.");
            error_count++;
        end
        rst = 1'b0; // De-assert reset
        data_valid = 1'b0;
        @(posedge clk);

        // 7. Final Result
        if (error_count == 0) begin
            $display("TESTS PASSED");
        end else begin
            $error("TEST FAILED with %0d errors.", error_count);
        end

        $finish;
    end

endmodule
