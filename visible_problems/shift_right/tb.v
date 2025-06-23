`timescale 1ns / 1ps

module tb;

    // Parameters matching the DUT's implicit configuration
    localparam NUM_SYMBOLS  = 10;
    localparam SYMBOL_WIDTH = 5;
    localparam SHIFT_WIDTH  = 3;
    localparam VEC_WIDTH    = NUM_SYMBOLS * SYMBOL_WIDTH;
    localparam MAX_VALID_SHIFT = 4;

    // Testbench signals
    reg [VEC_WIDTH-1:0]   in;
    reg [SHIFT_WIDTH-1:0] shift;
    reg [SYMBOL_WIDTH-1:0]fill;
    wire[VEC_WIDTH-1:0]   out;
    wire                  out_valid;

    // DUT Instantiation
    shift_right dut (
        .out_valid(out_valid),
        .in(in),
        .shift(shift),
        .fill(fill),
        .out(out)
    );

    // Testbench variables
    integer errors = 0;
    integer test_count = 0;
    reg [VEC_WIDTH-1:0]   expected_out;
    reg                   expected_out_valid;
    reg [VEC_WIDTH-1:0]   patterned_in;

    // Task to apply stimulus, calculate expected results, and check correctness
    task apply_and_check(string test_name);
        // 1. Calculate golden model results
        expected_out_valid = (shift <= MAX_VALID_SHIFT);

        if (expected_out_valid) begin
            for (int i = 0; i < NUM_SYMBOLS; i++) begin
                if (i < (NUM_SYMBOLS - shift)) begin
                    // This part gets data from the input vector
                    expected_out[i*SYMBOL_WIDTH +: SYMBOL_WIDTH] = in[(i + shift)*SYMBOL_WIDTH +: SYMBOL_WIDTH];
                end else begin
                    // This part gets filled
                    expected_out[i*SYMBOL_WIDTH +: SYMBOL_WIDTH] = fill;
                end
            end
        end else begin
            // If the shift amount is invalid, the output data is don't-care.
            // We only check that out_valid is low.
            expected_out = {VEC_WIDTH{1'bx}};
        end

        // 2. Apply stimulus and wait for combinational logic to settle
        #1;

        // 3. Compare DUT output with expected results
        test_count++;
        if (out_valid !== expected_out_valid) begin
            errors++;
            $display("------------------------------------------------------------------");
            $display("ERROR in Test #%0d: %s", test_count, test_name);
            $display("  [FAIL] out_valid mismatch!");
            $display("  INPUTS: shift=%d", shift);
            $display("  EXPECTED: out_valid=%b", expected_out_valid);
            $display("  GOT:      out_valid=%b", out_valid);
            $display("------------------------------------------------------------------");
        end

        // Only check data output if the shift was valid
        if (expected_out_valid) begin
            if (out !== expected_out) begin
                errors++;
                $display("------------------------------------------------------------------");
                $display("ERROR in Test #%0d: %s", test_count, test_name);
                $display("  [FAIL] Shifted output data mismatch!");
                $display("  INPUTS: in=0x%h, shift=%d, fill=0x%h", in, shift, fill);
                $display("  EXPECTED: out=0x%h", expected_out);
                $display("  GOT:      out=0x%h", out);
                $display("------------------------------------------------------------------");
            end
        end
    endtask

    initial begin
        // Initialize inputs
        in = 0;
        shift = 0;
        fill = 0;

        // Create a patterned input where symbol 'i' has value 'i'
        // patterned_in = { 5'd9, 5'd8, ..., 5'd1, 5'd0 }
        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            patterned_in[i*SYMBOL_WIDTH +: SYMBOL_WIDTH] = i;
        end

        // --- TEST CASES ---

        // Test 1: Zero shift (pass-through)
        in = patterned_in;
        shift = 0;
        fill = 5'h1F; // Fill value should be ignored
        apply_and_check("Zero Shift (Pass-through)");

        // Test 2: Basic valid shift
        in = patterned_in;
        shift = 2;
        fill = 5'hA; // Fill with 10101
        apply_and_check("Basic Valid Shift (shift=2)");

        // Test 3: Maximum valid shift (boundary condition)
        in = patterned_in;
        shift = 4;
        fill = 5'hC; // Fill with 01100
        apply_and_check("Maximum Valid Shift (shift=4)");

        // Test 4: Minimum invalid shift (boundary condition)
        in = patterned_in;
        shift = 5;
        fill = 5'h5;
        apply_and_check("Minimum Invalid Shift (shift=5)");

        // Test 5: Other invalid shifts
        in = patterned_in;
        shift = 6;
        fill = 5'h5;
        apply_and_check("Invalid Shift (shift=6)");
        shift = 7;
        apply_and_check("Invalid Shift (shift=7)");

        // Test 6: Shift with all-zero input
        in = 50'd0;
        shift = 3;
        fill = 5'h11; // Fill with 10001
        apply_and_check("Shift with Zero Input");
        
        // Test 7: Shift with all-one input
        in = {VEC_WIDTH{1'b1}};
        shift = 1;
        fill = 5'd0;
        apply_and_check("Shift with Ones Input, Zero Fill");
        
        // Test 8: Randomized valid shifts
        for (int i = 0; i < 5; i++) begin
            in = {$random, $random};
            shift = $urandom_range(0, MAX_VALID_SHIFT);
            fill = $random;
            apply_and_check($sformatf("Randomized Valid Shift #%0d", i+1));
        end

        // --- FINAL REPORT ---
        #5;
        if (errors == 0) begin
            $display("------------------------------------------------------------------");
            $display("All %0d tests completed.", test_count);
            $display("TESTS PASSED");
            $display("------------------------------------------------------------------");
        end else begin
            $display("------------------------------------------------------------------");
            $display("TESTBENCH FAILED with %0d error(s) out of %0d tests.", errors, test_count);
            $display("------------------------------------------------------------------");
        end

        $finish;
    end

endmodule
