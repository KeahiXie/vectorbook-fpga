module strategy_risk_array_p4 #(
    parameter int NUM_SYMBOLS = 8,
    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 32
)
(
    input  logic clk,
    input  logic rst,

    // indexed in — straight from order_book_array
    input  logic [NUM_SYMBOLS-1:0]    book_valid,
    input  logic [NUM_SYMBOLS-1:0]    book_update,
    input  logic [PRICE_WIDTH-1:0]    best_bid_price    [0: NUM_SYMBOLS-1],
    input  logic [QUANTITY_WIDTH-1:0] best_bid_quantity [0: NUM_SYMBOLS-1],
    input  logic [PRICE_WIDTH-1:0]    best_ask_price    [0: NUM_SYMBOLS-1],
    input  logic [QUANTITY_WIDTH-1:0] best_ask_quantity [0: NUM_SYMBOLS-1],

    // broadcast config — shared across symbols (per-symbol config is post-Phase-6 scope)
    input  logic [PRICE_WIDTH-1:0]    min_spread,
    input  logic [7:0]                threshold_numerator,    
    input  logic [7:0]                threshold_denominator,
    input  logic [QUANTITY_WIDTH-1:0] order_quantity,
    input  logic                      trading_enable,
    input  logic                      kill_switch,
    input  logic [QUANTITY_WIDTH-1:0] max_quantity,

    // indexed out
    output logic [NUM_SYMBOLS-1:0]    order_valid,
    output logic [NUM_SYMBOLS-1:0]    order_side,
    output logic [PRICE_WIDTH-1:0]    order_price        [0: NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0] order_quantity_out [0: NUM_SYMBOLS-1],  // _out avoids the config-input collision
    output logic [1:0]                rejected_reason    [0: NUM_SYMBOLS-1]
);

genvar i;
generate
for (i =0; i < NUM_SYMBOLS; i = i + 1) begin: gen_sr
    logic strat_proposal_valid, strat_proposal_side;
    logic [PRICE_WIDTH-1:0] strat_proposal_price;
    logic [QUANTITY_WIDTH-1:0] strat_proposal_quantity;

    strategy_p4 #(.QUANTITY_WIDTH(QUANTITY_WIDTH), .PRICE_WIDTH(PRICE_WIDTH)) u_strategy(
        .clk                   (clk),
        .rst                   (rst),
        .book_valid            (book_valid[i]),
        .book_update           (book_update[i]),
        .best_bid_price        (best_bid_price[i]),
        .best_ask_price        (best_ask_price[i]),
        .best_bid_quantity     (best_bid_quantity[i]),
        .best_ask_quantity     (best_ask_quantity[i]),
        .min_spread            (min_spread),
        .threshold_numerator   (threshold_numerator),
        .threshold_denominator (threshold_denominator),
        .order_quantity        (order_quantity),
        .proposal_valid        (strat_proposal_valid),
        .proposal_side         (strat_proposal_side),
        .proposal_price        (strat_proposal_price),
        .proposal_quantity     (strat_proposal_quantity)

    );

    risk_p4 #(.QUANTITY_WIDTH(QUANTITY_WIDTH), .PRICE_WIDTH(PRICE_WIDTH)) u_risk(
        .clk               (clk),
        .rst               (rst),
        .proposal_valid    (strat_proposal_valid),
        .proposal_side     (strat_proposal_side),
        .proposal_quantity (strat_proposal_quantity),
        .proposal_price    (strat_proposal_price),
        .trading_enable    (trading_enable),
        .kill_switch       (kill_switch),
        .max_quantity      (max_quantity),
        .order_valid       (order_valid[i]),
        .order_side        (order_side[i]),
        .order_price       (order_price[i]),
        .order_quantity    (order_quantity_out[i]),
        .rejected_reason   (rejected_reason[i])
    );
    end
endgenerate

endmodule

