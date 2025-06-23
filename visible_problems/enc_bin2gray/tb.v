`timescale 1ns / 1ps

module tb;

    // Parameters for the testbench
    localparam WIDTH = 10;
    localparam NUM_TEST_VECTORS = 1 << WIDTH;

    // Testbench signals
    reg  [WIDTH-1:0] bin;
    wire [WIDTH-1:0] gray;
    
    // Instantiate the Device Under Test (DUT)
    enc_bin2gray dut (
        .bin(bin),
        .gray(gray)
    );

    // Main verification block
    initial begin
        integer i;
        reg [WIDTH-1:0] expected_gray;

        // An exhaustive test is performed for all 2^10 = 1024 possible inputs.
        // This single loop is sufficient to detect all described functional bugs,
        // including incorrect bitwise operations, shift direction errors, MSB
        // handling errors, and signed vs. unsigned arithmetic shift bugs.
        for (i = 0; i < NUM_TEST_VECTORS; i = i + 1) begin
            // Drive the input vector
            bin = i;
            
            // Calculate the expected golden value based on the specification
            expected_gray = bin ^ (bin >> 1);
            
            // Wait for combinatorial logic to propagate and settle
            #1;
            
            // Compare the DUT's output with the expected golden value
            if (gray !== expected_gray) begin
                $display("-------------------------------------------");
                $display("ERROR: Mismatch detected at time %0t ns.", $time);
                $display("  Input bin     = %d'b%b", WIDTH, bin);
                $display("  DUT output    = %d'b%b", WIDTH, gray);
                $display("  Expected gray = %d'b%b", WIDTH, expected_gray);
                $display("-------------------------------------------");
                $error("TEST FAILED: Data mismatch.");
                $finish;
            end
        end
        
        // If the loop completes without any errors, the test is successful.
        $display("TESTS PASSED");
        $finish;
    end

endmodule
