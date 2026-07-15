// Description  :Testbench for minimarket_top
// Date         :2026-7-15

`timescale 1ns/1ps



module mini_market_top_tb();

    // creating a clock signal
    logic clk;
    logic rst;
    logic[7:0] data_in;
    logic byte_valid;
    logic ready;
    logic book_valid;
    logic book_update;
    logic[15:0] best_bid_price;
    logic[15:0] best_ask_price;
    logic[7:0] best_bid_quantity;
    logic[7:0] best_ask_quantity;

    mini_market_top dut(
        .clk(clk),
        .rst(rst),
        .byte_valid(byte_valid),
        .data_in(data_in),
        .ready(ready),
        .book_valid(book_valid),
        .book_update(book_update),
        .best_bid_price(best_bid_price),
        .best_ask_price(best_ask_price),
        .best_bid_quantity(best_bid_quantity),
        .best_ask_quantity(best_ask_quantity)
    );


    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;

        byte_valid <= 1'b0;


        #100;
        $finish;
    end

endmodule