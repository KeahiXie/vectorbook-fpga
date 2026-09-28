/*
This is the phase 4 top-level module.

It connects the ITCH parser to the BRAM-based order book.

Flow:
ITCH bytes -> parser -> order_book -> best bid/ask

The FIFO and strategy/risk modules will be connected later.
*/


module phase_4_top #(
    parameter int NUM_SYMBOLS = 4,

    parameter int FIFO_DEPTH = 64,

    // Order-store parameters
    parameter int ORDER_NUM_BANKS   = 3,
    parameter int ORDER_TABLE_DEPTH = 128,
    parameter int ORDER_ADDR_WIDTH  = $clog2(ORDER_TABLE_DEPTH),
    parameter int ORDER_ENTRY_WIDTH = 144,

    // Order-level parameters
    parameter int LEVEL_NUM_PROBES     = 3,
    parameter int PRICE_WIDTH          = 32,
    parameter int QUANTITY_WIDTH       = 32,
    parameter int COUNT_WIDTH          = 16,
    parameter int LEVEL_TABLE_DEPTH    = 128,
    parameter int LEVEL_ADDR_WIDTH     = $clog2(LEVEL_TABLE_DEPTH),
    parameter int LEVEL_ENTRY_WIDTH    =
        8 + 1 + PRICE_WIDTH + QUANTITY_WIDTH + COUNT_WIDTH + 7
)
(
    input logic clk,
    input logic rst,

    // Incoming ITCH byte stream
    input  logic       byte_valid,
    output logic       byte_read,
    input  logic [7:0] data_in,

    // Best bid
    output logic [PRICE_WIDTH-1:0]      best_bid_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0]   best_bid_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0]      best_bid_order_count [0:NUM_SYMBOLS-1],
    output logic                        best_bid_valid [0:NUM_SYMBOLS-1],

    // Best ask
    output logic [PRICE_WIDTH-1:0]      best_ask_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0]   best_ask_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0]      best_ask_order_count [0:NUM_SYMBOLS-1],
    output logic                        best_ask_valid [0:NUM_SYMBOLS-1],
    output logic operation_done,

    // Parser error
    output logic       parser_error_valid,
    output logic [3:0] parser_error_code,

    // Order-store error
    output logic       order_store_error_valid,
    output logic [3:0] order_store_error_code,

    // Order-level error
    output logic       order_level_error_valid,
    output logic [3:0] order_level_error_code,
    
   // Strategy configuration
    input logic [PRICE_WIDTH-1:0]      min_spread,
    input logic [7:0]                  threshold_numerator,
    input logic [7:0]                  threshold_denominator,
    input logic [QUANTITY_WIDTH-1:0]   strategy_order_quantity,

    // Risk configuration
    input logic                        trading_enable,
    input logic                        kill_switch,
    input logic [QUANTITY_WIDTH-1:0]   max_quantity,

    // Strategy/risk outputs
    output logic [NUM_SYMBOLS-1:0]     order_valid,
    output logic [NUM_SYMBOLS-1:0]     order_side,
    output logic [PRICE_WIDTH-1:0]
        order_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0]
        order_quantity_out [0:NUM_SYMBOLS-1],
    output logic [1:0]
        rejected_reason [0:NUM_SYMBOLS-1]

);

    // FIFO -> Parser
    logic [7:0] fifo_out;
    logic       fifo_byte_valid;
    logic       parser_byte_read;

    // Parser -> Order Book
    logic        parser_event_valid;
    logic        parser_event_ready;
    logic [2:0]  parser_event_operation;
    logic [63:0] parser_event_order_id;
    logic [63:0] parser_event_new_order_id;
    logic [7:0]  parser_event_symbol;
    logic        parser_event_side;
    logic [31:0] parser_event_price;
    logic [31:0] parser_event_quantity;
    
    // Strategy and Risk Module

    logic [NUM_SYMBOLS-1:0] strategy_book_valid;
    logic [NUM_SYMBOLS-1:0] strategy_book_update;
    logic [7:0] updated_symbol;

    // Input byte FIFO
    sync_fifo_p4 #(
        .DEPTH(FIFO_DEPTH)
    ) u_input_fifo (
        .clk             (clk),
        .rst             (rst),
        // upstream -> FIFO
        .data_in         (data_in),
        .byte_valid      (byte_valid),
        .fifo_ready      (byte_read),
        // FIFO -> parser
        .parser_ready    (parser_byte_read),
        .fifo_out        (fifo_out),
        .fifo_byte_valid (fifo_byte_valid)
    );

    // ITCH Parser
    itch_parser_p3 #(
        .NUM_SYMBOLS(NUM_SYMBOLS)
    ) u_itch_parser (
        .clk                (clk),
        .rst                (rst),

        .byte_valid         (fifo_byte_valid),
        .byte_read          (parser_byte_read),
        .data_in            (fifo_out),

        .event_valid        (parser_event_valid),
        .event_ready        (parser_event_ready),

        .event_operation    (parser_event_operation),
        .event_order_id     (parser_event_order_id),
        .event_new_order_id (parser_event_new_order_id),
        .event_symbol       (parser_event_symbol),
        .event_side         (parser_event_side),
        .event_price        (parser_event_price),
        .event_quantity     (parser_event_quantity),

        .error_valid        (parser_error_valid),
        .error_code         (parser_error_code)
    );


    // Order Book
    order_book_p3 #(
        .NUM_SYMBOLS          (NUM_SYMBOLS),

        .ORDER_NUM_BANKS      (ORDER_NUM_BANKS),
        .ORDER_TABLE_DEPTH    (ORDER_TABLE_DEPTH),
        .ORDER_ADDR_WIDTH     (ORDER_ADDR_WIDTH),
        .ORDER_ENTRY_WIDTH    (ORDER_ENTRY_WIDTH),

        .LEVEL_NUM_PROBES     (LEVEL_NUM_PROBES),
        .PRICE_WIDTH          (PRICE_WIDTH),
        .QUANTITY_WIDTH       (QUANTITY_WIDTH),
        .COUNT_WIDTH          (COUNT_WIDTH),
        .LEVEL_TABLE_DEPTH    (LEVEL_TABLE_DEPTH),
        .LEVEL_ADDR_WIDTH     (LEVEL_ADDR_WIDTH),
        .LEVEL_ENTRY_WIDTH    (LEVEL_ENTRY_WIDTH)
    ) u_order_book (
        .clk                       (clk),
        .rst                       (rst),

        .parser_event_valid        (parser_event_valid),
        .parser_event_ready        (parser_event_ready),
        .parser_event_operation    (parser_event_operation),
        .parser_event_order_id     (parser_event_order_id),
        .parser_event_new_order_id (parser_event_new_order_id),
        .parser_event_symbol       (parser_event_symbol),
        .parser_event_side         (parser_event_side),
        .parser_event_price        (parser_event_price),
        .parser_event_quantity     (parser_event_quantity),

        .best_bid_price            (best_bid_price),
        .best_bid_quantity         (best_bid_quantity),
        .best_bid_order_count      (best_bid_order_count),
        .best_bid_valid            (best_bid_valid),

        .best_ask_price            (best_ask_price),
        .best_ask_quantity         (best_ask_quantity),
        .best_ask_order_count      (best_ask_order_count),
        .best_ask_valid            (best_ask_valid),

        .operation_done            (operation_done),

        .order_store_error_valid   (order_store_error_valid),
        .order_store_error_code    (order_store_error_code),

        .order_level_error_valid   (order_level_error_valid),
        .order_level_error_code    (order_level_error_code)
    );
    
    // Strategy and Risk Array
        //1. Capture the symbol when parser event is being accepted
    always_ff @(posedge clk) begin
        if (rst) begin
            updated_symbol <= '0;
        end
        else if (parser_event_valid && parser_event_ready) begin
            updated_symbol <= parser_event_symbol;
        end
    end

        //2. 
    always_comb begin
        strategy_book_valid  = '0;
        strategy_book_update = '0;

        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            strategy_book_valid[i] =
                best_bid_valid[i] && best_ask_valid[i];
        end

        if (operation_done &&
            !order_store_error_valid &&
            updated_symbol < 8'(NUM_SYMBOLS)) begin

            strategy_book_update[updated_symbol] = 1'b1;
        end
    end   

    strategy_risk_array_p4 #(
        .NUM_SYMBOLS    (NUM_SYMBOLS),
        .PRICE_WIDTH    (PRICE_WIDTH),
        .QUANTITY_WIDTH (QUANTITY_WIDTH)
    ) u_strategy_risk_array (
        .clk                   (clk),
        .rst                   (rst),

        .book_valid            (strategy_book_valid),
        .book_update           (strategy_book_update),

        .best_bid_price        (best_bid_price),
        .best_bid_quantity     (best_bid_quantity),
        .best_ask_price        (best_ask_price),
        .best_ask_quantity     (best_ask_quantity),

        .min_spread            (min_spread),
        .threshold_numerator   (threshold_numerator),
        .threshold_denominator (threshold_denominator),
        .order_quantity        (strategy_order_quantity),

        .trading_enable        (trading_enable),
        .kill_switch           (kill_switch),
        .max_quantity          (max_quantity),

        .order_valid           (order_valid),
        .order_side            (order_side),
        .order_price           (order_price),
        .order_quantity_out    (order_quantity_out),
        .rejected_reason       (rejected_reason)
    );
endmodule