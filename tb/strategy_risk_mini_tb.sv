module strategy_risk_mini_tb ();

    logic clk = 0;
    logic rst;
    // output from one_symbol_book to strategy_mini
    logic book_valid;
    logic book_update;
    logic [15:0] best_bid_price;
    logic [15:0] best_ask_price;
    logic [7:0] best_bid_quantity;
    logic [7:0] best_ask_quantity;
    // inputs for strategy_mini
    logic [15:0] min_spread;
    logic [7:0] threshold_numerator;
    logic [7:0] threshold_denominator;
    logic[7:0] s_order_quantity;
    // internal signals/outputs from strategy_mini
    logic proposal_valid;
    logic proposal_side; 
    logic [15:0] proposal_price;
    logic [7:0] proposal_quantity;
    // inputs for risk_mini
    logic trading_enable ;
    logic kill_switch ;
    logic [7:0] max_quantity ;
    // output for risk_mini
    logic order_valid ;
    logic order_side ;
    logic[15:0] order_price ;
    logic[7:0] out_order_quantity ;
    logic[1:0] rejected_reason;


    // clock generator
    always #5 clk = ~clk;

    strategy_mini u_strategy(
        .clk(clk),
        .rst(rst),
        .book_valid(book_valid),
        .book_update(book_update),
        .best_bid_price(best_bid_price),
        .best_ask_price(best_ask_price),
        .best_bid_quantity(best_bid_quantity),
        .best_ask_quantity(best_ask_quantity),

        .min_spread(min_spread),
        .threshold_numerator(threshold_numerator),
        .threshold_denominator(threshold_denominator),
        .order_quantity(s_order_quantity),

        .proposal_valid(proposal_valid),
        .proposal_side(proposal_side),
        .proposal_quantity(proposal_quantity),
        .proposal_price(proposal_price)
    );

    risk_mini u_risk(
        .clk(clk),
        .rst(rst),
        .proposal_valid(proposal_valid),
        .proposal_side(proposal_side),
        .proposal_quantity(proposal_quantity),
        .proposal_price(proposal_price),

        .trading_enable(trading_enable),
        .kill_switch(kill_switch),
        .max_quantity(max_quantity),

        .order_valid(order_valid),
        .order_side(order_side),
        .order_price(order_price),
        .order_quantity(out_order_quantity),
        .rejected_reason(rejected_reason)

    );

    task send_book_update(
        input [15:0] bid_p, input [7:0] bid_q,
        input [15:0] ask_p, input [7:0] ask_q
    );
        @(posedge clk);
        best_bid_price    <= bid_p;
        best_bid_quantity <= bid_q;
        best_ask_price    <= ask_p;
        best_ask_quantity <= ask_q;
        book_update       <= 1'b1;
        @(posedge clk);
        book_update       <= 1'b0;

    endtask

    initial begin

        // reset
        rst <= 1'b1;
        book_update <= 1'b0;
        book_valid  <= 1'b0;
        repeat(2) @(posedge clk)
        rst <= 1'b0;

        // strategy mini config
        min_spread <= 5;
        threshold_numerator <= 2;
        threshold_denominator <= 1;
        s_order_quantity <= 50;
        
        
        // risk mini config
        max_quantity <= 100;
        trading_enable <= 1;
        kill_switch <= 0;

        // V1: bid 1000/120, ask 1020/40 -> accept, buy, reason=0
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);

        // V2: bid 1000/40, ask 1010/130 -> accept, sell, reason=0
        send_book_update(16'h03E8, 8'h28, 16'h03F2, 8'h82);

        // V3: bid 1000/100, ask 1002/100 -> no order (spread=2 < 5)
        send_book_update(16'h03E8, 8'h64, 16'h03EA, 8'h64);
        
        // V4: kill switch is on -> no order, resason = 2 
        repeat(2) @(posedge clk);
        kill_switch <= 1'b1;
        threshold_numerator <= 1;
        threshold_denominator <= 1;
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);

        // V5: order more than what its allowed -> no order, reason = 1 
        s_order_quantity = 150;
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);

        // V6: tie - no proposal 
        send_book_update(16'h03E8, 8'h32, 16'h03F2, 8'h32);


        


        

        




    end

endmodule

