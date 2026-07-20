module order_book_array_p1 #(
  parameter int NUM_SYMBOLS    = 8,
  parameter int PRICE_WIDTH    = 32,
  parameter int QUANTITY_WIDTH = 16
) (
  input  logic clk,
  input  logic rst,

  input  logic                       event_valid,
  input  logic [7:0]                 event_symbol,
  input  logic [PRICE_WIDTH-1:0]     event_bid_price,
  input  logic [QUANTITY_WIDTH-1:0]  event_bid_quantity,
  input  logic [PRICE_WIDTH-1:0]     event_ask_price,
  input  logic [QUANTITY_WIDTH-1:0]  event_ask_quantity,

  output logic [NUM_SYMBOLS-1:0]    book_valid,
  output logic [NUM_SYMBOLS-1:0]    book_update,
  // frist time using logic array here, similar ways to implement this is structure
  output logic [PRICE_WIDTH-1:0]    best_bid_price    [NUM_SYMBOLS],
  output logic [QUANTITY_WIDTH-1:0] best_bid_quantity [NUM_SYMBOLS],
  output logic [PRICE_WIDTH-1:0]    best_ask_price    [NUM_SYMBOLS],
  output logic [QUANTITY_WIDTH-1:0] best_ask_quantity [NUM_SYMBOLS]
);

genvar i;
generate
  for (i = 0; i < NUM_SYMBOLS; i = i+1) begin: gen_book
    order_book_p1 #(
      .TRACKED_SYMBOL(i),
      .PRICE_WIDTH(PRICE_WIDTH),
      .QUANTITY_WIDTH(QUANTITY_WIDTH)
    ) u_book(
      .clk(clk),
      .rst(rst),
      // boardcasting to each book not routing(could be an update for future)
      .event_ask_price( event_ask_price),
      .event_bid_price(event_bid_price),
      .event_ask_quantity(event_ask_quantity),
      .event_bid_quantity(event_bid_quantity),
      .event_valid(event_valid),
      .event_symbol(event_symbol),
      .book_valid(book_valid[i]),
      .book_update(book_update[i]),
      .best_bid_price(best_bid_price[i]),
      .best_ask_price(best_ask_price[i]),
      .best_ask_quantity(best_ask_quantity[i]),
      .best_bid_quantity(best_bid_quantity[i])
      

    );
  end

endgenerate


endmodule

