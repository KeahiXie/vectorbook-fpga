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
    logic V1, V2, V3, V4, V5, V6;


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
    
    // new function for seeing the sim result in console instead of through waveforms 
    task check_order(
        input logic exp_valid,
        input logic exp_side,
        input logic[1:0] exp_reason,
        input string label
    );
    
        if ((exp_valid !== order_valid) || 
            (rejected_reason !== exp_reason) || 
            (exp_valid && (exp_side !== order_side))  )begin
            $display("FAIL[%s]: valid=%b, side=%b, reason=%d", label, order_valid, order_side, rejected_reason);
        end else
            $display("PASS[%s]", label);
        
    
    endtask
    
    initial begin

        // reset
        rst <= 1'b1;
        book_update <= 1'b0;
        book_valid  <= 1'b0;
        repeat(2) @(posedge clk);
        rst <= 1'b0;
        
        book_valid <= 1'b1;

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
        V1 <= 1'b1;
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);
        repeat(1) @(posedge clk);
        #1;
        check_order(1'b1, 1'b0, 2'd0, "V1 buy accepted");
        V1 <= 1'b0;

        // V2: bid 1000/40, ask 1010/130 -> accept, sell, reason=0
        V2 <= 1'b1;
        send_book_update(16'h03E8, 8'h28, 16'h03F2, 8'h82);
        repeat(1) @(posedge clk);
        #1;
        check_order(1'b1, 1'b1, 2'd0, "V2 sell accepted");
        V2 <= 1'b0;

        // V3: bid 1000/100, ask 1002/100 -> no order (spread=2 < 5)
        V3 <= 1'b1;
        send_book_update(16'h03E8, 8'h64, 16'h03EA, 8'h64);
        repeat(2) @(posedge clk);
        #1;
        check_order(1'b0, 1'b0, 2'd0, "V3 spread too small, silent");
        V3 <= 1'b0;

        // V4: kill switch is on -> no order, reason = 2
        V4 <= 1'b1;
        repeat(2) @(posedge clk);
        kill_switch <= 1'b1;
        threshold_numerator <= 1;
        threshold_denominator <= 1;
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);
        repeat(1) @(posedge clk);
        #1;
        check_order(1'b0, 1'b0, 2'd2, "V4 killed");
        V4 <= 1'b0;

        // V5: order more than allowed -> no order, reason = 3
        V5 <= 1'b1;
        kill_switch <= 1'b0;
        s_order_quantity <= 150;
        send_book_update(16'h03E8, 8'h78, 16'h03FC, 8'h28);
        repeat(1) @(posedge clk);
        #1;
        check_order(1'b0, 1'b0, 2'd3, "V5 over max quantity");
        V5 <= 1'b0;

        // V6: tie - no proposal at all
        V6 <= 1'b1;
        send_book_update(16'h03E8, 8'h32, 16'h03F2, 8'h32);
        repeat(2) @(posedge clk);
        #1;
        check_order(1'b0, 1'b0, 2'd0, "V6 tie, silent");
        V6 <= 1'b0;

        // T2: spread exactly == min_spread (1000 -> 1005) -> proposal fires (>= inclusive)
        s_order_quantity <= 8'd50;
        send_book_update(16'h03E8, 8'h78, 16'h03ED, 8'h28);
        repeat(1) @(posedge clk);
        #1;
        check_order(1'b1, 1'b0, 2'd0, "T2 boundary spread==min, buy accepted");

        repeat(4) @(posedge clk);
        $finish;

       
    end

endmodule

