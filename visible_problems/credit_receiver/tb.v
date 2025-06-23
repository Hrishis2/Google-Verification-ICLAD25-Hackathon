`timescale 1ns / 1ps

module tb;

    // Testbench signals
    reg         clk;
    reg         rst;
    reg         push_sender_in_reset;
    reg         push_credit_stall;
    reg         push_valid;
    reg         pop_credit;
    reg         credit_initial;
    reg         credit_withhold;
    reg  [7:0]  push_data;

    wire        push_receiver_in_reset;
    wire        push_credit;
    wire        pop_valid;
    wire        credit_count;
    wire        credit_available;
    wire [7:0]  pop_data;
    
    // Instantiate the DUT
    credit_receiver dut (
        .clk                    (clk),
        .rst                    (rst),
        .push_sender_in_reset   (push_sender_in_reset),
        .push_receiver_in_reset (push_receiver_in_reset),
        .push_credit_stall      (push_credit_stall),
        .push_credit            (push_credit),
        .push_valid             (push_valid),
        .pop_credit             (pop_credit),
        .pop_valid              (pop_valid),
        .credit_initial         (credit_initial),
        .credit_withhold        (credit_withhold),
        .credit_count           (credit_count),
        .credit_available       (credit_available),
        .push_data              (push_data),
        .pop_data               (pop_data)
    );

    // Clock generation
    parameter CLK_PERIOD = 10;
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Helper task for checking conditions
    task check;
        input condition;
        input [255:0] message;
        if (!condition) begin
            $display("ASSERTION FAILED @ %0t: %s", $time, message);
            $finish;
        end
    endtask

    // Main test sequence
    initial begin
        // -----------------------------------------------------------------
        // Initial state and Reset Test
        // -----------------------------------------------------------------
        $display("Test 1: Reset behavior");
        rst <= 1;
        push_sender_in_reset <= 0;
        push_credit_stall <= 0;
        push_valid <= 1;
        pop_credit <= 0;
        credit_initial <= 1;
        credit_withhold <= 0;
        push_data <= 8'hA1;

        #(CLK_PERIOD);
        check(push_receiver_in_reset === 1, "T1.1: push_receiver_in_reset must be 1 when rst is 1");
        check(pop_valid === 0, "T1.2: pop_valid must be 0 during rst");
        check(push_credit === 0, "T1.3: push_credit must be 0 during rst");
        check(credit_count === 1, "T1.4: credit_count must be credit_initial during rst");
        check(pop_data === push_data, "T1.5: pop_data must combinatorially follow push_data");

        rst <= 0;
        credit_initial <= 0; // Value should not affect counter after reset de-assertion
        #(0.1); // Let combinational logic settle
        check(push_receiver_in_reset === 0, "T1.6: push_receiver_in_reset must be 0 after rst de-asserts");
        check(pop_valid === 1, "T1.7: pop_valid must pass through after rst de-asserts");
        
        @(posedge clk);
        check(credit_count === 0, "T1.8: credit_count must decrement after one push_credit cycle");

        // -----------------------------------------------------------------
        // Test `push_sender_in_reset`
        // -----------------------------------------------------------------
        $display("Test 2: Sender reset behavior");
        push_sender_in_reset <= 1;
        credit_initial <= 1;
        push_valid <= 1;
        
        #(CLK_PERIOD);
        check(push_receiver_in_reset === 0, "T2.1: push_receiver_in_reset must reflect rst only");
        check(pop_valid === 0, "T2.2: pop_valid must be 0 during sender reset");
        check(push_credit === 0, "T2.3: push_credit must be 0 during sender reset");
        check(credit_count === 1, "T2.4: credit_count must be credit_initial during sender reset");

        push_sender_in_reset <= 0;
        #(0.1);
        check(pop_valid === 1, "T2.5: pop_valid must pass through after sender reset de-asserts");
        
        // -----------------------------------------------------------------
        // Test combinational data path
        // -----------------------------------------------------------------
        $display("Test 3: Combinational path verification");
        push_valid <= 0;
        #(0.1);
        check(pop_valid === 0, "T3.1: pop_valid should be 0 when push_valid is 0");
        push_data <= 8'hD5;
        #(0.1);
        check(pop_data === 8'hD5, "T3.2: pop_data must update combinatorially");
        push_valid <= 1;
        #(0.1);
        check(pop_valid === 1, "T3.3: pop_valid must be 1 when push_valid is 1");
        push_valid <= 0;

        // -----------------------------------------------------------------
        // Test credit counter logic
        // -----------------------------------------------------------------
        $display("Test 4: Credit counter operations");

        // Start with 0 credits
        @(posedge clk);
        check(credit_count === 0, "T4.1: Credit count should be 0 after previous credit was sent");
        
        // Increment credit
        pop_credit <= 1;
        @(posedge clk);
        pop_credit <= 0;
        check(credit_count === 1, "T4.2: Credit count should increment on pop_credit");
        
        // Decrement credit
        check(push_credit === 1, "T4.3: push_credit should be high when a credit is available");
        @(posedge clk);
        check(credit_count === 0, "T4.4: Credit count should decrement when push_credit is sent");
        check(push_credit === 0, "T4.5: push_credit should be low when no credits are available");

        // Saturation (Overflow) Test
        $display("Test 5: Credit counter saturation");
        push_credit_stall <= 1; // Block credit from being sent
        pop_credit <= 1;
        @(posedge clk);
        check(credit_count === 1, "T5.1: Credit count increments to 1");
        pop_credit <= 1;
        @(posedge clk);
        pop_credit <= 0;
        check(credit_count === 1, "T5.2: Credit count must saturate at 1 (not overflow to 0)");
        push_credit_stall <= 0;

        // Simultaneous Increment and Decrement Test
        $display("Test 6: Simultaneous credit increment and decrement");
        check(credit_count === 1, "T6.1: Starting with 1 credit");
        check(push_credit === 1, "T6.2: push_credit is active");
        pop_credit <= 1; // Request increment
        @(posedge clk);
        pop_credit <= 0;
        check(credit_count === 1, "T6.3: Credit count should remain 1 on simultaneous inc/dec");
        
        // -----------------------------------------------------------------
        // Test credit control signals (`credit_withhold`, `push_credit_stall`)
        // -----------------------------------------------------------------
        $display("Test 7: Credit control signals");
        check(credit_count === 1, "T7.1: Starting with 1 credit");

        // Test credit_withhold
        credit_withhold <= 1;
        #(0.1); // Combinational check
        check(credit_available === 0, "T7.2: credit_available should be 0 when withheld");
        check(push_credit === 0, "T7.3: push_credit should be 0 when credit is withheld");
        @(posedge clk);
        check(credit_count === 1, "T7.4: credit_count is not decremented when withheld");
        credit_withhold <= 0;
        #(0.1);
        check(credit_available === 1, "T7.5: credit_available becomes 1 after withhold is removed");
        check(push_credit === 1, "T7.6: push_credit becomes 1 after withhold is removed");
        
        // Test push_credit_stall
        push_credit_stall <= 1;
        #(0.1);
        check(push_credit === 0, "T7.7: push_credit should be 0 when stalled");
        @(posedge clk);
        check(credit_count === 1, "T7.8: credit_count is not decremented when stalled");
        push_credit_stall <= 0;
        #(0.1);
        check(push_credit === 1, "T7.9: push_credit becomes 1 after stall is removed");
        
        // -----------------------------------------------------------------
        // Test Reset Priority over clock edge update
        // -----------------------------------------------------------------
        $display("Test 8: Reset priority");
        credit_initial <= 0;
        @(posedge clk);
        check(credit_count === 0, "T8.1: Credit count decremented to 0");
        
        // Schedule reset and pop_credit to happen at the same time
        rst <= 1;
        pop_credit <= 1; 
        credit_initial <= 1;
        @(posedge clk);
        rst <= 0;
        pop_credit <= 0;
        check(credit_count === 1, "T8.2: Counter must take reset value, not incremented value");

        // -----------------------------------------------------------------
        // Final Checks
        // -----------------------------------------------------------------
        $display("TESTS PASSED");
        $finish;
    end

endmodule
