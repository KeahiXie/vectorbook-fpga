//------------------------------------------------------------------
// risk_mini decision table (priority order, first match wins)
//
// | proposal_valid | trading_enable | kill_switch | qty > max | outcome | rejected_reason      |
// |----------------|----------------|-------------|-----------|---------|----------------------|
// |       0        |       x        |      x      |     x     | no order| 0 (idle)             |
// |       1        |       0        |      x      |     x     | reject  | 1 (trading disabled) |
// |       1        |       1        |      1      |     x     | reject  | 2 (kill switch)      |
// |       1        |       1        |      0      |     1     | reject  | 3 (exceeds max qty)  |
// |       1        |       1        |      0      |     0     | ACCEPT  | 0 (no rejection)     |
//
// x = don't care. Accepts are signaled by order_valid=1, not by
// rejected_reason - reason 0 is shared between "idle" and "accepted",

module risk_p4 #(
    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 16
)

(
    input logic clk,
    input logic rst,

    input logic proposal_valid,
    input logic proposal_side,
    input logic[QUANTITY_WIDTH-1:0] proposal_quantity,
    input logic[PRICE_WIDTH-1:0] proposal_price,

    input logic trading_enable,
    input logic kill_switch,
    input logic [QUANTITY_WIDTH-1:0] max_quantity,
    
    output logic order_valid,
    output logic order_side,
    output logic[PRICE_WIDTH-1:0] order_price,
    output logic[QUANTITY_WIDTH-1:0] order_quantity,
    output logic[1:0] rejected_reason 
    // 0 - succeed;        1 - trading not enable
    // 2 - kill switch is on    3 - exceed max quantity 
);
    always_ff @(posedge clk) begin
        order_valid <= 1'b0; // false by default
        if (rst) begin
            order_valid <= 1'b0;
            order_side <= 1'b0;
            order_price <= '0;
            order_quantity <= '0;
            rejected_reason <= '0;
        end

        else if (proposal_valid) begin
            if (trading_enable) begin
                if (!kill_switch) begin
                    if (proposal_quantity <= max_quantity ) begin
                        order_valid <= 1'b1;
                        rejected_reason <= 2'd0; // succeed
                        order_price <= proposal_price;
                        order_side <= proposal_side;
                        order_quantity <= proposal_quantity;

                    end else begin
                        order_valid <= 1'b0;
                        rejected_reason <= 2'd3; // exceed
                    end

                end else begin
                    order_valid <= 1'b0;
                    rejected_reason <= 2'd2; // killed
                end

                
            end else begin
                order_valid <= 1'b0;
                rejected_reason <= 2'd1; // trading not enable
            end
            
        end else begin
            order_valid <= 1'b0;
            rejected_reason <= 2'd0;
        end




    end

endmodule


// en | kill | max | accept |
// 0                   NO
// 1    1        X      NO
// 1    0       1       NO(MAX)
// 1    0       0.      YES
