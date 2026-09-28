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

    //4, Test sequence 
    `include "itch_sender_task.svh"
    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        // ID 1, stock locate 100, buy, quantity 10, raw price 100
        send_add(64'd1, 16'd100, 1'b0, 32'd10, 32'd100);

        // sending bytes is finished; wait for the book update
        wait (operation_done == 1'b1);

        if (best_bid_valid[0] !== 1'b1 ||
            best_bid_price[0] !== 32'd100 ||
            best_bid_quantity[0] !== 32'd10 ||
            best_bid_order_count[0] !== 16'd1) begin

            $fatal(1, "ADD failed: valid=%b price=%0d quantity=%0d count=%0d",
                best_bid_valid[0],
                best_bid_price[0],
                best_bid_quantity[0],
                best_bid_order_count[0]);
        end

        $display("PASS: first ADD");

        $display("Best bid: valid=%b price=%0d quantity=%0d count=%0d",
            best_bid_valid[0],
            best_bid_price[0],
            best_bid_quantity[0],
            best_bid_order_count[0]);

        $finish;
    end

endmodule;

