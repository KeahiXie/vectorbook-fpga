module order_book_p1 # (
    parameter logic[7:0] TRACKED_SYMBOL = 8'd0,
    parameter int QUANTITY_WIDTH = 16,
    parameter int PRICE_WIDTH = 32
)
(
    input logic clk,
    input logic rst,
    input logic event_valid,
    input  logic [7:0]  event_symbol,
    input logic[PRICE_WIDTH-1:0] event_bid_price, 
    input logic[PRICE_WIDTH-1:0] event_ask_price,
    input logic[QUANTITY_WIDTH-1:0]  event_bid_quantity,
    input logic[QUANTITY_WIDTH-1:0]  event_ask_quantity,

    output logic book_valid ,  
    output logic book_update, 
    output logic[PRICE_WIDTH-1:0] best_bid_price,
    output logic[QUANTITY_WIDTH-1:0] best_bid_quantity,
    output logic[PRICE_WIDTH-1:0] best_ask_price,
    output logic[QUANTITY_WIDTH-1:0] best_ask_quantity

);

logic write_en;
assign write_en = (event_valid && (event_symbol == TRACKED_SYMBOL));


always_ff @(posedge clk) begin

        book_update <= 1'b0;

        if (rst) begin
            book_valid <= 1'b0;
            best_bid_price <= '0;
            best_ask_price <= '0;
            best_ask_quantity <= '0;
            best_bid_quantity <= '0;
        end

        else if (write_en) begin
            best_bid_price <= event_bid_price;
            best_bid_quantity <= event_bid_quantity;
            best_ask_price <= event_ask_price;
            best_ask_quantity <= event_ask_quantity;
            book_valid <= 1'b1;
            book_update <= 1'b1;           
        end
        

end


endmodule


