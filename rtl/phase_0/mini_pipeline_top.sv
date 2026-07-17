//-----------------------------------------------------------
//Pipeline: byte stream -> quote7_parser -> one_symbol_book 
//          ->  strategy_mini -> risk_mini -> approved order
//-----------------------------------------------------------   



module mini_pipeline_top (
    input  logic        clk,
    input  logic        rst,

    // Incoming 7-byte quote stream
    input  logic        byte_valid,
    input  logic [7:0]  data_in,
    output logic        ready,

    // Strategy configuration
    input  logic [15:0] min_spread,
    input  logic [7:0]  threshold_numerator,
    input  logic [7:0]  threshold_denominator,
    input  logic [7:0]  strategy_order_quantity,

    // Risk configuration
    input  logic        trading_enable,
    input  logic        kill_switch,
    input  logic [7:0]  max_quantity,

    // Book observation outputs
    output logic        book_valid,
    output logic        book_update,
    output logic [15:0] best_bid_price,
    output logic [7:0]  best_bid_quantity,
    output logic [15:0] best_ask_price,
    output logic [7:0]  best_ask_quantity,

    // Strategy observation outputs
    output logic        proposal_valid,
    output logic        proposal_side,
    output logic [15:0] proposal_price,
    output logic [7:0]  proposal_quantity,

    // Final risk-approved order outputs
    output logic        order_valid,
    output logic        order_side,
    output logic [15:0] order_price,
    output logic [7:0]  order_quantity,
    output logic [1:0]  rejected_reason
);

    // Parser -> book event wires
    logic [7:0]  event_symbol;
    logic        event_valid;
    logic [15:0] event_bid_price;
    logic [7:0]  event_bid_quantity;
    logic [15:0] event_ask_price;
    logic [7:0]  event_ask_quantity;

    //-------------------------------------------------------------------------
    // Stage 1: Convert seven incoming bytes into one complete quote event.
    //-------------------------------------------------------------------------
    quote7_parser parser (
        .clk                (clk),
        .rst                (rst),
        .byte_valid         (byte_valid),
        .data_in            (data_in),
        .ready              (ready),
        .event_symbol       (event_symbol),
        .event_valid        (event_valid),
        .event_bid_price    (event_bid_price),
        .event_ask_price    (event_ask_price),
        .event_bid_quantity (event_bid_quantity),
        .event_ask_quantity (event_ask_quantity)
    );

    //-------------------------------------------------------------------------
    // Stage 2: Store the latest quote for the selected symbol.
    //-------------------------------------------------------------------------
    one_symbol_book book (
        .clk                (clk),
        .rst                (rst),
        .event_valid        (event_valid),
        .event_symbol       (event_symbol),
        .event_bid_price    (event_bid_price),
        .event_bid_quantity (event_bid_quantity),
        .event_ask_price    (event_ask_price),
        .event_ask_quantity (event_ask_quantity),
        .book_valid         (book_valid),
        .book_update        (book_update),
        .best_bid_price     (best_bid_price),
        .best_bid_quantity  (best_bid_quantity),
        .best_ask_price     (best_ask_price),
        .best_ask_quantity  (best_ask_quantity)
    );

    //-------------------------------------------------------------------------
    // Stage 3: Generate a buy or sell proposal from the updated book.
    //-------------------------------------------------------------------------
    strategy_mini strategy (
        .clk                   (clk),
        .rst                   (rst),
        .book_valid            (book_valid),
        .book_update           (book_update),
        .best_bid_price        (best_bid_price),
        .best_ask_price        (best_ask_price),
        .best_bid_quantity     (best_bid_quantity),
        .best_ask_quantity     (best_ask_quantity),
        .min_spread            (min_spread),
        .threshold_numerator   (threshold_numerator),
        .threshold_denominator (threshold_denominator),
        .order_quantity        (strategy_order_quantity),
        .proposal_valid        (proposal_valid),
        .proposal_side         (proposal_side),
        .proposal_price        (proposal_price),
        .proposal_quantity     (proposal_quantity)
    );

    //-------------------------------------------------------------------------
    // Stage 4: Accept or reject the strategy proposal using risk controls.
    //-------------------------------------------------------------------------
    risk_mini risk (
        .clk               (clk),
        .rst               (rst),
        .proposal_valid    (proposal_valid),
        .proposal_side     (proposal_side),
        .proposal_quantity (proposal_quantity),
        .proposal_price    (proposal_price),
        .trading_enable    (trading_enable),
        .kill_switch       (kill_switch),
        .max_quantity      (max_quantity),
        .order_valid       (order_valid),
        .order_side        (order_side),
        .order_price       (order_price),
        .order_quantity    (order_quantity),
        .rejected_reason   (rejected_reason)
    );

endmodule