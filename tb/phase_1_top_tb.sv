`timescale 1ns/1ps

module phase_1_top_tb #(
    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 16,
    parameter int NUM_SYMBOLS = 8
) ();

    // clk generator
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst;

    // simulated data input from market
    logic [7:0] data_in;
    logic byte_valid;
    logic ready;

    // strategy and risk config
    logic [PRICE_WIDTH-1:0]    min_spread;
    logic [7:0]                threshold_numerator, threshold_denominator;
    logic [QUANTITY_WIDTH-1:0] order_quantity, max_quantity;
    logic                      trading_enable, kill_switch;

    // output from the pipeline
    logic [NUM_SYMBOLS-1:0]    order_valid, order_side;
    logic [PRICE_WIDTH-1:0]    order_price        [NUM_SYMBOLS];
    logic [QUANTITY_WIDTH-1:0] order_quantity_out [NUM_SYMBOLS];
    logic [1:0]                rejected_reason    [NUM_SYMBOLS];

    task send_byte(input logic [7:0] b);
    
        @(negedge clk);
        data_in    = b;
        byte_valid = 1'b1;
        @(posedge clk);
        while (!ready) @(posedge clk);
    endtask

    task send_message(
        input logic[7:0] symbol,
        input logic[PRICE_WIDTH-1:0] bid_price,
        input logic[QUANTITY_WIDTH-1:0] bid_qty,
        input logic[PRICE_WIDTH-1:0] ask_price,
        input logic[QUANTITY_WIDTH-1:0] ask_qty
    );
        send_byte(symbol);
        for (int b = PRICE_WIDTH-8; b>=0; b-=8) send_byte(bid_price[b +: 8]);
        for (int b = QUANTITY_WIDTH-8; b>=0; b-=8) send_byte(bid_qty[b +: 8]);
        for (int b = PRICE_WIDTH-8; b>=0; b-=8) send_byte(ask_price[b +: 8]);
        for (int b = QUANTITY_WIDTH-8; b>=0; b-=8) send_byte(ask_qty[b +: 8]);
        
        @(posedge clk);
        byte_valid = 1'b0;
        data_in    = 8'h00;
    endtask


    task check_order(
        input int idx,
        input logic exp_valid, input logic exp_side, input logic [1:0] exp_reason,
        input string label
    );
    int latency;
    latency = 0;

    // latency count
    while (!order_valid[idx] && latency < 40) begin
        @(posedge clk);
        latency++;
    end

    if ((exp_valid !== order_valid[idx]) ||
        (rejected_reason[idx] !== exp_reason) ||
        (exp_valid && (exp_side != order_side[idx])) ||
        ($countones(order_valid) > 1))
        begin
            $display("FAIL[%s]:valid=%b side=%b reason=%d latency=%0d cycles",  label, order_valid[idx], order_side[idx], rejected_reason[idx], latency);    
        end

        else begin
            $display("PASS[%s]: latency= %d cycles", label, latency);
        end
    endtask






    phase_1_top #(.NUM_SYMBOLS(NUM_SYMBOLS), .PRICE_WIDTH(PRICE_WIDTH), .QUANTITY_WIDTH(QUANTITY_WIDTH)) dut (
    .clk(clk), 
    .rst(rst),
    .data_in(data_in), 
    .byte_valid(byte_valid), 
    .ready(ready),
    .min_spread(min_spread), 
    .threshold_numerator(threshold_numerator),
    .threshold_denominator(threshold_denominator), 
    .order_quantity(order_quantity),
    .trading_enable(trading_enable), 
    .kill_switch(kill_switch), 
    .max_quantity(max_quantity),
    .order_valid(order_valid), 
    .order_side(order_side), 
    .order_price(order_price),
    .order_quantity_out(order_quantity_out), 
    .rejected_reason(rejected_reason)
  );


    initial begin
        time t0;
        t0 = $time;
        rst <= 1'b1;
        byte_valid <= 1'b0;
        repeat(2) @(posedge clk);
        rst <= 1'b0;

        //strategy and risk config
        min_spread <= 5; threshold_numerator <= 2; 
        threshold_denominator <= 1;order_quantity <= 50; 
        max_quantity <= 100; trading_enable <= 1; kill_switch <= 0;

        // V1 analog ” symbol 3, bid 1000/120, ask 1020/40 -> buy accepted
        send_message(8'd3, 1000, 120, 1020, 40);
        check_order(3, 1'b1, 1'b0, 2'd0, "V1 buy accepted, symbol 3");
        $display("V1 full-chain latency: %0d cycles", ($time - t0)/10);

        repeat(4) @(posedge clk);
        $finish;


    end

endmodule