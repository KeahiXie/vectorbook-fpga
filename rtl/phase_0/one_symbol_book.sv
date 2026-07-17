//------------------------------
// Module       : one_symbol_book
// Name         : Keahi Xie
// Created      : 2026-07-14
// Purpose      : Holds the most recent top-of-book quote for a single symbol
// Description  : Consumes complete quote events form quote7_parser and latches those matching
//                the spcific symbol. Events for other symbols are ignored.All four fields are replaced together as one
// Interfaces   : book_valid - level; low until the first matching event. 
//                book_update - pulse; high for exactly one cycle when there's a write happens
//                best_* - stable between updates; meaningless if !book_valid
// Further plans: upgrade it to support multiple symbols
// Revisions    : 2026-07-14 KX Initial version
//                2026-07-15 KX Deleted unnecessary register; removed bid/ask comparison gating
//                              added power-on value for book_valid



module one_symbol_book(
    input logic clk,
    input logic rst,
    input logic event_valid,
    input  logic [7:0]  event_symbol,
    input  logic [15:0] event_bid_price,
    input  logic [7:0]  event_bid_quantity,
    input  logic [15:0] event_ask_price,
    input  logic [7:0]  event_ask_quantity,

    output logic book_valid = 1'b0,  //handle trash value stored in the register before sending any quote
    output logic book_update, //notify the system when there's an update on this cycle
    output logic[15:0] best_bid_price,
    output logic[7:0] best_bid_quantity,
    output logic[15:0] best_ask_price,
    output logic[7:0] best_ask_quantity
    
);

    // bid and ask update flag, useful for book_update logic 
    logic write_en;
    assign write_en = event_valid && (event_symbol == 8'h02);

    

    always_ff@(posedge clk) begin
        
        book_update <= 1'b0;

        if (rst) begin
            book_valid <= 1'b0;
            best_bid_price <= 16'd0;
            best_ask_price <= 16'd0;
            best_ask_quantity <= 8'd0;
            best_bid_quantity <= 8'd0;
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