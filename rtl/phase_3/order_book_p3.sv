module order_book_p3 #(
    parameter int NUM_SYMBOLS = 4,

    // Order-store parameters
    parameter int ORDER_NUM_BANKS   = 3,
    parameter int ORDER_TABLE_DEPTH = 128,
    parameter int ORDER_ADDR_WIDTH  = $clog2(ORDER_TABLE_DEPTH),
    parameter int ORDER_ENTRY_WIDTH = 144,

    // Order-level parameters
    parameter int LEVEL_NUM_PROBES     = 3,
    parameter int PRICE_WIDTH          = 32,
    parameter int QUANTITY_WIDTH       = 32,
    parameter int COUNT_WIDTH          = 16,
    parameter int LEVEL_TABLE_DEPTH    = 128,
    parameter int LEVEL_ADDR_WIDTH     = $clog2(LEVEL_TABLE_DEPTH),
    parameter int LEVEL_ENTRY_WIDTH    =
        8 + 1 + PRICE_WIDTH + QUANTITY_WIDTH + COUNT_WIDTH + 7
)(
    input logic clk,
    input logic rst,

    // Incoming ITCH byte stream
    input  logic       byte_valid,
    output logic       byte_read,
    input  logic [7:0] data_in,

    // ---------------------------------------------------------
    // Order-store BRAM interface
    // ---------------------------------------------------------
    input  logic [ORDER_ENTRY_WIDTH-1:0]
        order_store_read_data [0:ORDER_NUM_BANKS-1],
    input  logic order_store_read_valid,

    output logic [ORDER_ADDR_WIDTH-1:0] order_store_read_addr,
    output logic [ORDER_NUM_BANKS-1:0]  order_store_read_en,

    output logic [ORDER_ENTRY_WIDTH-1:0]
        order_store_write_data [0:ORDER_NUM_BANKS-1],
    output logic [ORDER_ADDR_WIDTH-1:0] order_store_write_addr,
    output logic [ORDER_NUM_BANKS-1:0]  order_store_write_en,

    // ---------------------------------------------------------
    // Order-level BRAM interface
    // ---------------------------------------------------------
    input  logic [LEVEL_ENTRY_WIDTH-1:0] order_level_read_data,
    input  logic                         order_level_read_valid,

    output logic                         order_level_read_en,
    output logic [LEVEL_ADDR_WIDTH-1:0]  order_level_read_addr,

    output logic                         order_level_write_en,
    output logic [LEVEL_ADDR_WIDTH-1:0]  order_level_write_addr,
    output logic [LEVEL_ENTRY_WIDTH-1:0] order_level_write_data,

    // ---------------------------------------------------------
    // Best bid
    // ---------------------------------------------------------
    output logic [PRICE_WIDTH-1:0]
        best_bid_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0]
        best_bid_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0]
        best_bid_order_count [0:NUM_SYMBOLS-1],
    output logic
        best_bid_valid [0:NUM_SYMBOLS-1],

    // ---------------------------------------------------------
    // Best ask
    // ---------------------------------------------------------
    output logic [PRICE_WIDTH-1:0]
        best_ask_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0]
        best_ask_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0]
        best_ask_order_count [0:NUM_SYMBOLS-1],
    output logic
        best_ask_valid [0:NUM_SYMBOLS-1],

    // ---------------------------------------------------------
    // Final operation status
    // order_store_operation_done now occurs only after
    // order_level has completed its update.
    // ---------------------------------------------------------
    output logic operation_done,

    // Parser error
    output logic       parser_error_valid,
    output logic [3:0] parser_error_code,

    // Order-store error
    output logic       order_store_error_valid,
    output logic [3:0] order_store_error_code,

    // Order-level error
    output logic       order_level_error_valid,
    output logic [3:0] order_level_error_code
);

    // =========================================================
    // Parser -> Order Store
    // =========================================================
    logic        parser_event_valid;
    logic        parser_event_ready;
    logic [2:0]  parser_event_operation;
    logic [63:0] parser_event_order_id;
    logic [63:0] parser_event_new_order_id;
    logic [7:0]  parser_event_symbol;
    logic        parser_event_side;
    logic [31:0] parser_event_price;
    logic [31:0] parser_event_quantity;

    // =========================================================
    // Order Store -> Order Level
    // =========================================================
    logic               level_update_valid;
    logic               level_update_ready;
    logic               level_update_done;
    logic [7:0]         level_update_symbol;
    logic               level_update_side;
    logic [31:0]        level_update_price;
    logic signed [32:0] level_update_quantity;
    logic signed [1:0]  level_update_order_count;


    // =========================================================
    // ITCH Parser
    // =========================================================
    itch_parser_p3 #(
        .NUM_SYMBOLS(NUM_SYMBOLS)
    ) u_itch_parser (
        .clk                (clk),
        .rst                (rst),

        .byte_valid         (byte_valid),
        .byte_read          (byte_read),
        .data_in            (data_in),

        .event_valid        (parser_event_valid),
        .event_ready        (parser_event_ready),

        .event_operation    (parser_event_operation),
        .event_order_id     (parser_event_order_id),
        .event_new_order_id (parser_event_new_order_id),
        .event_symbol       (parser_event_symbol),
        .event_side         (parser_event_side),
        .event_price        (parser_event_price),
        .event_quantity     (parser_event_quantity),

        .error_valid        (parser_error_valid),
        .error_code         (parser_error_code)
    );


    // =========================================================
    // Individual Order Store
    // =========================================================
    order_store_p3 #(
        .NUM_BANKS   (ORDER_NUM_BANKS),
        .TABLE_DEPTH (ORDER_TABLE_DEPTH),
        .ADDR_WIDTH  (ORDER_ADDR_WIDTH),
        .ENTRY_WIDTH (ORDER_ENTRY_WIDTH)
    ) u_order_store (
        .clk                     (clk),
        .rst                     (rst),

        .event_valid             (parser_event_valid),
        .event_ready             (parser_event_ready),

        .event_operation         (parser_event_operation),
        .event_order_id          (parser_event_order_id),
        .event_new_order_id      (parser_event_new_order_id),
        .event_symbol            (parser_event_symbol),
        .event_side              (parser_event_side),
        .event_price             (parser_event_price),
        .event_quantity          (parser_event_quantity),

        .read_data               (order_store_read_data),
        .read_valid              (order_store_read_valid),
        .read_addr               (order_store_read_addr),
        .read_en                 (order_store_read_en),

        .write_data              (order_store_write_data),
        .write_addr              (order_store_write_addr),
        .write_en                (order_store_write_en),

        .operation_done          (operation_done),
        .error_valid             (order_store_error_valid),
        .error_code              (order_store_error_code),

        .order_level_valid       (level_update_valid),
        .order_level_ready       (level_update_ready),
        .order_level_done        (level_update_done),

        .order_level_symbol      (level_update_symbol),
        .order_level_side        (level_update_side),
        .order_level_price       (level_update_price),
        .order_level_quantity    (level_update_quantity),
        .order_level_order_count (level_update_order_count)
    );


    // =========================================================
    // Price-Level Store
    // =========================================================
    order_level_p3 #(
        .NUM_SYMBOLS    (NUM_SYMBOLS),
        .NUM_PROBES     (LEVEL_NUM_PROBES),
        .PRICE_WIDTH    (PRICE_WIDTH),
        .QUANTITY_WIDTH (QUANTITY_WIDTH),
        .COUNT_WIDTH    (COUNT_WIDTH),
        .TABLE_DEPTH    (LEVEL_TABLE_DEPTH),
        .ADDR_WIDTH     (LEVEL_ADDR_WIDTH),
        .ENTRY_WIDTH    (LEVEL_ENTRY_WIDTH)
    ) u_order_level (
        .clk                     (clk),
        .rst                     (rst),

        .order_level_valid       (level_update_valid),
        .order_level_ready       (level_update_ready),
        .order_level_symbol      (level_update_symbol),
        .order_level_side        (level_update_side),
        .order_level_price       (level_update_price),
        .order_level_quantity    (level_update_quantity),
        .order_level_order_count (level_update_order_count),

        .read_data               (order_level_read_data),
        .read_valid              (order_level_read_valid),
        .read_en                 (order_level_read_en),
        .read_addr               (order_level_read_addr),

        .write_en                (order_level_write_en),
        .write_addr              (order_level_write_addr),
        .write_data              (order_level_write_data),

        .best_bid_price          (best_bid_price),
        .best_bid_quantity       (best_bid_quantity),
        .best_bid_order_count    (best_bid_order_count),
        .best_bid_valid          (best_bid_valid),

        .best_ask_price          (best_ask_price),
        .best_ask_quantity       (best_ask_quantity),
        .best_ask_order_count    (best_ask_order_count),
        .best_ask_valid          (best_ask_valid),

        .operation_done          (level_update_done),
        .error_valid             (order_level_error_valid),
        .error_code              (order_level_error_code)
    );

endmodule
