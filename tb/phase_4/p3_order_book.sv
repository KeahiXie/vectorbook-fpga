`timescale 1ns/1ps




module p_3_order_book_tb();

    // 1.Signals
    logic clk = '0;
    logic rst = 1'b1;

    logic byte_valid = 1'b0;
    logic [7:0] data_in = '0;
    logic byte_read;

    logic operation_done;

    // best bid for each of the four symbols
    logic [31:0] best_bid_price [0:3];
    logic [31:0] best_bid_quantity [0:3];
    logic [15:0] best_bid_order_count [0:3];
    logic best_bid_valid [0:3];

    // best ask
    logic [31:0] best_ask_price [0:3];
    logic [31:0] best_ask_quantity [0:3];
    logic [15:0] best_ask_order_count [0:3];
    logic best_ask_valid [0:3];

    // error signals
    logic parser_error_valid;
    logic [3:0] parser_error_code;

    logic order_store_error_valid;
    logic [3:0] order_store_error_code;

    logic order_level_error_valid;
    logic [3:0] order_level_error_code;


    // 2. Clock Generator 
    always #4 clk = ~clk;

    //3. DUT
    order_book_p3 dut (
        .clk                     (clk),
        .rst                     (rst),

        .byte_valid              (byte_valid),
        .byte_read               (byte_read),
        .data_in                 (data_in),

        .best_bid_price          (best_bid_price),
        .best_bid_quantity       (best_bid_quantity),
        .best_bid_order_count    (best_bid_order_count),
        .best_bid_valid          (best_bid_valid),

        .best_ask_price          (best_ask_price),
        .best_ask_quantity       (best_ask_quantity),
        .best_ask_order_count    (best_ask_order_count),
        .best_ask_valid          (best_ask_valid),

        .operation_done          (operation_done),

        .parser_error_valid      (parser_error_valid),
        .parser_error_code       (parser_error_code),

        .order_store_error_valid (order_store_error_valid),
        .order_store_error_code  (order_store_error_code),

        .order_level_error_valid (order_level_error_valid),
        .order_level_error_code  (order_level_error_code)
    );

   //4. Test sequence
     // remember BRAM writes for displaying tables
    // these are testbench copies, not direct BRAM readbacks
    `include "itch_sender_task.svh"
    `include "book_table_tasks.svh"
    initial begin

        repeat (4) @(negedge clk);
        rst = 1'b0;

        @(negedge clk);

        $display("\nADD ID 1: buy 10 at 100");
        send_add(64'd1, 16'd100, 1'b0, 32'd10, 32'd100);
        check_bid(32'd100, 32'd10, 16'd1);

        // same price, quantity and count should increase
        $display("\nADD ID 2: buy 20 at 100");
        send_add(64'd2, 16'd100, 1'b0, 32'd20, 32'd100);
        check_bid(32'd100, 32'd30, 16'd2);

        // lower bid should not change the best bid
        $display("\nADD ID 3: buy 5 at 99");
        send_add(64'd3, 16'd100, 1'b0, 32'd5, 32'd99);
        check_bid(32'd100, 32'd30, 16'd2);

        // replace the lower bid with a new best bid
        $display("\nREPLACE ID 3 with ID 4: buy 15 at 101");
        send_replace(64'd3, 64'd4, 16'd100, 32'd15, 32'd101);
        check_bid(32'd101, 32'd15, 16'd1);

        // move another order to the existing best level
        $display("\nREPLACE ID 1 with ID 5: buy 7 at 101");
        send_replace(64'd1, 64'd5, 16'd100, 32'd7, 32'd101);
        check_bid(32'd101, 32'd22, 16'd2);

        // look up a replacement using its new ID
        // ID 5 remains at 101, so that level is not removed
        $display("\nREPLACE ID 4 with ID 6: buy 12 at 102");
        send_replace(64'd4, 64'd6, 16'd100, 32'd12, 32'd102);
        check_bid(32'd102, 32'd12, 16'd1);

        $display("\nPASS: all ADD and REPLACE checks");
        $finish;
    end 

    always @(posedge clk) begin
        if (!rst) begin

            if (parser_error_valid)
                $fatal(1, "Parser error: %0d", parser_error_code);

            if (order_store_error_valid)
                $fatal(1, "Order store error: %0d",
                    order_store_error_code);

            if (order_level_error_valid)
                $fatal(1, "Order level error: %0d",
                    order_level_error_code);

        end
    end

endmodule;

