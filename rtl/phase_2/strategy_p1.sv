// Since author don't familiar with market microstrecture, therefore only two strategy will be implemented here:
// 1. Trancation only happen when the spread bigger than pre-set min spread
// 2. Order Book/Flow Imbalance 

// ------------------------------------------------------------------
// strategy_mini decision table (priority order, first match wins)
//
// proposal_en = book_valid && book_update
// spread_ok   = (spread >= min_spread) && (best_ask_price > best_bid_price)
//
// | proposal_en | spread_ok | buy_signal | sell_signal | outcome                                  |
// |-------------|-----------|------------|-------------|------------------------------------------|
// |      0      |     x     |     x      |      x      | no propose - nothing evaluated this cycle|
// |      1      |     0     |     x      |      x      | no propose - Gate A fails                |
// |      1      |     1     |     1      |      1      | no propose - tie, ambiguous direction    |
// |      1      |     1     |     0      |      0      | no propose - neither side clears         |
// |      1      |     1     |     1      |      0      | BUY  @ best_ask_price, qty=order_quantity|
// |      1      |     1     |     0      |      1      | SELL @ best_bid_price, qty=order_quantity|
//
// x = don't care. Each else-if branch only checks what's new for its

module strategy_p1 #(
    parameter int QUANTITY_WIDTH = 16,
    parameter int PRICE_WIDTH = 32
)
(
    input logic clk,
    input logic rst,
    input logic book_valid,
    input logic book_update,

    input logic [PRICE_WIDTH-1:0] best_bid_price,
    input logic [PRICE_WIDTH-1:0] best_ask_price,
    input logic [QUANTITY_WIDTH-1:0] best_bid_quantity,
    input logic [QUANTITY_WIDTH-1:0] best_ask_quantity,

    input logic [PRICE_WIDTH-1:0] min_spread,
    // we use threshold_numrator and denomiantor here to replace threshold ratio
    // to avoid division
    // bid / ask > ratio means bid at least X times bigger than ask
    input logic [7:0] threshold_numerator,
    input logic [7:0] threshold_denominator,
    input logic[QUANTITY_WIDTH-1:0] order_quantity,

    output logic proposal_valid,
    output logic proposal_side, // 0 = buy, 1 = sell
    output logic [PRICE_WIDTH-1:0] proposal_price,
    output logic [QUANTITY_WIDTH-1:0] proposal_quantity
);
    logic proposal_en;
    logic[PRICE_WIDTH-1:0] spread;
    logic buy_signal, sell_signal;
    logic[QUANTITY_WIDTH+7:0] bid_times_denom, ask_times_num, ask_times_denom, bid_times_num;

    assign proposal_en = (book_valid && book_update);
    assign spread = best_ask_price - best_bid_price;
    assign bid_times_denom = best_bid_quantity* threshold_denominator;
    assign ask_times_num = best_ask_quantity* threshold_numerator;
    assign ask_times_denom = best_ask_quantity * threshold_denominator;
    assign bid_times_num = best_bid_quantity * threshold_numerator;
    assign buy_signal = bid_times_denom >= ask_times_num;
    assign sell_signal = ask_times_denom >= bid_times_num;

    always_ff @(posedge clk) begin
        proposal_valid <= 1'b0;

        // rest branch
        if (rst) begin
            proposal_valid <= 1'b0;
            proposal_price <= '0;
            proposal_quantity <= '0;
            proposal_side <= 1'b0;
        end

        // only propose when book is valid and there's an update in the book
        else if (proposal_en) begin
            // only propose when spread not less than min_spread
            if (spread >= min_spread && (best_ask_price > best_bid_price)) begin
                
                if (buy_signal && sell_signal) begin
                    proposal_valid <= 1'b0;
                end

                else if (buy_signal) begin
                    proposal_side <= 1'b0;
                    proposal_price <= best_ask_price;
                    proposal_quantity <= order_quantity;
                    proposal_valid <= 1'b1;
                end 

                else if (sell_signal) begin
                    proposal_side <= 1'b1;
                    proposal_price <= best_bid_price;
                    proposal_quantity <= order_quantity;
                    proposal_valid <= 1'b1;
                end

                else begin
                    proposal_valid <= 1'b0;
                end
            end
            
        end

        else begin
            proposal_valid <= 1'b0;
        end
    end



endmodule
