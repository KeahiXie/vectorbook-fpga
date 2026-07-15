//-----------
// Module.  : mini_market_top
// Author   : Keahi Xie
// Date     : 2026-07-15
// Purpose  : top level to Wires quote7_parser and one_symbol_book together


module mini_market_top(
    input logic clk,
    input logic rst,
    input logic byte_valid,
    input logic[7:0] data_in,

    output logic ready,
    output logic book_valid,
    output logic book_update,
    output logic[15:0] best_bid_price,
    output logic[7:0] best_bid_quantity,
    output logic[15:0] best_ask_price,
    output logic[7:0] best_ask_quantity
);
    logic[7:0] event_symbol, event_ask_quantity, event_bid_quantity;
    logic[15:0] event_ask_price, event_bid_price;
    logic event_valid;

    quote7_parser parser(
        .clk(clk),
        .rst(rst),
        .byte_valid(byte_valid),
        .data_in(data_in),
        .ready(ready),
        .event_symbol(event_symbol),
        .event_valid(event_valid),
        .event_bid_price(event_bid_price),
        .event_ask_price(event_ask_price),
        .event_bid_quantity(event_bid_quantity),
        .event_ask_quantity(event_ask_quantity)
    );

    one_symbol_book book(
        .clk(clk),
        .rst(rst),
        .event_valid(event_valid),
        .event_symbol(event_symbol),
        .event_bid_price(event_bid_price),
        .event_ask_price(event_ask_price),
        .event_bid_quantity(event_bid_quantity),
        .event_ask_quantity(event_ask_quantity),
        .book_update(book_update),
        .book_valid(book_valid),
        .best_ask_price(best_ask_price),
        .best_bid_price(best_bid_price),
        .best_bid_quantity(best_bid_quantity),
        .best_ask_quantity(best_ask_quantity)
        

    );
    
    
endmodule