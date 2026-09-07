module phase_2_top #(
    parameter int NUM_SYMBOLS = 4,
    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 16
) (
    input logic clk,
    input logic rst,

    // upstream data input
    input  logic [7:0] data_in,
    input  logic       byte_valid,
    

    //boardcasst config shared across all 8 symbol - could be a future upgrade 
    input  logic [PRICE_WIDTH-1:0]    min_spread,
    input  logic [7:0]                threshold_numerator,
    input  logic [7:0]                threshold_denominator,
    input  logic [QUANTITY_WIDTH-1:0] order_quantity,
    input  logic                      trading_enable,
    input  logic                      kill_switch,
    input  logic [QUANTITY_WIDTH-1:0] max_quantity,

    output logic fifo_ready,

      // final outputs — indexed per symbol
    output logic [NUM_SYMBOLS-1:0]    order_valid,
    output logic [NUM_SYMBOLS-1:0]    order_side,
    output logic [PRICE_WIDTH-1:0]    order_price        [NUM_SYMBOLS],
    output logic [QUANTITY_WIDTH-1:0] order_quantity_out [NUM_SYMBOLS],
    output logic [1:0]                rejected_reason    [NUM_SYMBOLS]
);

    // FIFO -> parser
    logic                   parser_ready;
    logic                   fifo_byte_valid;
    logic[7:0]              fifo_out;


    // parser -> book array 
    logic                      event_valid;
    logic [7:0]                event_symbol;
    logic [PRICE_WIDTH-1:0]    event_bid_price;
    logic [QUANTITY_WIDTH-1:0] event_bid_quantity;
    logic [PRICE_WIDTH-1:0]    event_ask_price;
    logic [QUANTITY_WIDTH-1:0] event_ask_quantity;



    // book array -> strategy_risk_array
    logic [NUM_SYMBOLS-1:0]     book_valid;
    logic [NUM_SYMBOLS-1:0]     book_update;
    logic [PRICE_WIDTH-1:0]     best_bid_price [NUM_SYMBOLS];
    logic [QUANTITY_WIDTH-1:0]  best_bid_quantity [NUM_SYMBOLS];
    logic [PRICE_WIDTH-1:0]     best_ask_price [NUM_SYMBOLS];
    logic [QUANTITY_WIDTH-1:0]  best_ask_quantity [NUM_SYMBOLS];

    sync_fifo u_fifo(
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .byte_valid(byte_valid),
        .fifo_ready(fifo_ready),
        .parser_ready(parser_ready),
        .fifo_out(fifo_out),
        .fifo_byte_valid(fifo_byte_valid)

    );

    parser_p2 #(.PRICE_WIDTH(PRICE_WIDTH), .QUANTITY_WIDTH(QUANTITY_WIDTH)) u_parser (
    .clk(clk), 
    .rst(rst),
    .byte_valid(fifo_byte_valid),
    .data_in(fifo_out), 
    .parser_ready(parser_ready),
    .event_valid(event_valid),
    .event_symbol(event_symbol),
    .event_bid_price(event_bid_price),
    .event_bid_quantity(event_bid_quantity),
    .event_ask_price(event_ask_price),
    .event_ask_quantity(event_ask_quantity)

    );

    order_book_array_p2 #(.NUM_SYMBOLS(NUM_SYMBOLS), .PRICE_WIDTH(PRICE_WIDTH), .QUANTITY_WIDTH(QUANTITY_WIDTH)) u_books (
    .clk(clk), 
    .rst(rst),
    .event_valid(event_valid),
    .event_symbol(event_symbol),
    .event_bid_price(event_bid_price),
    .event_bid_quantity(event_bid_quantity),
    .event_ask_price(event_ask_price),
    .event_ask_quantity(event_ask_quantity),

    //out
    .book_valid(book_valid),
    .book_update(book_update),
    .best_bid_price(best_bid_price),
    .best_bid_quantity(best_bid_quantity),
    .best_ask_price(best_ask_price),
    .best_ask_quantity(best_ask_quantity)


    );

    strategy_risk_array #(.NUM_SYMBOLS(NUM_SYMBOLS), .PRICE_WIDTH(PRICE_WIDTH), .QUANTITY_WIDTH(QUANTITY_WIDTH)) u_strategy_risk (
    .clk(clk), 
    .rst(rst),
    // book_* inputs: 
    .book_valid(book_valid),
    .book_update(book_update),
    .best_bid_price(best_bid_price),
    .best_bid_quantity(best_bid_quantity),
    .best_ask_price(best_ask_price),
    .best_ask_quantity(best_ask_quantity),
    // config inputs
    .min_spread(min_spread),
    .threshold_numerator(threshold_numerator),
    .threshold_denominator(threshold_denominator),
    .order_quantity(order_quantity),
    .trading_enable(trading_enable),
    .kill_switch(kill_switch),
    .max_quantity(max_quantity),
    // order_* outputs:
    .order_valid(order_valid),
    .order_side(order_side),
    .order_price(order_price),
    .order_quantity_out(order_quantity_out),
    .rejected_reason(rejected_reason)
    );

endmodule


