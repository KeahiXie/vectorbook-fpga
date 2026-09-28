/* 
We're moving on from a simplified parser to an ITCH supported parser.
The parser supports Add Order(A), Add Order with MPID(F), Order Cancel(X),
and ETC.(visit the repo README for full list), the parser will throw error
when it's accepting a unsupport operation. 

Since each operation has different data lengths so we no longer treat each 
data feed as fixed length, we need to introduce FSM in this parser to ensure
that we catch all the input. which is gonna introduce burst. We're gonna to 
add FIFO before the praser and after the parser under same handshake protocol

Supported Operations: A, F, X, E, C, D, U

A(Add Order): 

byte 0       message type = A

bytes 1-2    stock locate
bytes 3-4    tracking number
bytes 5-10   timestamp

bytes 11-18  order reference number
byte 19      buy/sell indicator
bytes 20-23  shares
bytes 24-31  stock
bytes 32-35  price

To implement the parser, we need at least the following state:
IDLE: accept the message-type byte  and select the expected length
COLLECT: count bytes and assemble fields
PUBLISH: hodl the completed event untill event-ready 
ERROR: stop after receiveing an unsupport message type

*/


module itch_parser_p3 #(
    parameter int NUM_SYMBOLS = 4
)(
    input logic clk,
    input logic rst,

    // Incoming ITCH byte stream
    input   logic byte_valid,
    output  logic byte_read,
    input   logic[7:0] data_in,

    // Normalized event sent to order_store_p3
    output  logic event_valid,
    input   logic event_ready,

    output  logic[2:0]  event_operation,
    output  logic[63:0] event_order_id,
    output  logic[63:0] event_new_order_id,
    output  logic[7:0]  event_symbol,
    output  logic       event_side,
    output  logic[31:0] event_price,
    output  logic[31:0] event_quantity,

    // Parser status
    output  logic error_valid,
    output  logic[3:0] error_code

);

    // Temporary stock locate values for testing
    // Replace with real Stock Locate values later
    parameter logic [15:0] LOCATE_0 = 16'd100;
    parameter logic [15:0] LOCATE_1 = 16'd101;
    parameter logic [15:0] LOCATE_2 = 16'd102;
    parameter logic [15:0] LOCATE_3 = 16'd103;

////////////////////////////// Hardcoded Parameter BEGIN
    // Normalized order_store operations
    localparam logic[2:0] OP_ADD        = 3'd0;
    localparam logic[2:0] OP_REDUCE     = 3'd1;
    localparam logic[2:0] OP_DELETE     = 3'd2;
    localparam logic[2:0] OP_REPLACE    = 3'd3;
    localparam logic[2:0] OP_INVALID    = 3'd4;

    // ITCH message types
    localparam logic[7:0] MSG_ADD               = "A";
    localparam logic[7:0] MSG_ADD_MPID          = "F";
    localparam logic[7:0] MSG_CANCEL            = "X";
    localparam logic[7:0] MSG_EXECUTE           = "E";
    localparam logic[7:0] MSG_EXECUTE_PRICE     = "C";
    localparam logic[7:0] MSG_DELETE            = "D";
    localparam logic[7:0] MSG_REPLACE           = "U";

    // ITCH Messgae lengths for each op
    localparam logic[7:0] LENGTH_ADD               = 8'd36;
    localparam logic[7:0] LENGTH_ADD_MPID          = 8'd40;
    localparam logic[7:0] LENGTH_CANCEL            = 8'd23;
    localparam logic[7:0] LENGTH_EXECUTE           = 8'd31;
    localparam logic[7:0] LENGTH_EXECUTE_PRICE     = 8'd36;
    localparam logic[7:0] LENGTH_DELETE            = 8'd19;
    localparam logic[7:0] LENGTH_REPLACE           = 8'd35;
////////////////////////////// Hardcoded Parameter END

////////////////////////////// Structures BEGIN
    // ERROR codes
    typedef enum logic[3:0] { 
        ERR_NONE                  = 4'h0,
        ERR_UNSUPPORTED_MESSGAE   = 4'h1,
        ERR_INVALID_STATE         = 4'hF
    } parser_error_t;

    parser_error_t error_code_reg;

    // Parser states
    typedef enum logic[1:0] { 
        ST_IDLE,
        ST_COLLECT,
        ST_PUBLISH,
        ST_ERROR
    } parser_state_t;

    parser_state_t state;
////////////////////////////// Structures END

////////////////////////////// Registers BEGIN
    logic [7:0] message_type_reg;
    logic [7:0] byte_count_reg;
    logic [7:0] expected_length_reg;

    // Temp registers for data input
    logic [15:0] stock_locate_reg;
    logic [63:0] order_id_reg;
    logic [63:0] new_order_id_reg; // only be used in Replace op
    logic        side_reg;
    logic [31:0] quantity_reg;
    logic [31:0] price_reg;
////////////////////////////// Registers END

////////////////////////////// Status BEGIN
    // only accept bytes while receiving a messgae
    assign byte_read = (state == ST_IDLE) || (state == ST_COLLECT);

    assign event_valid = (state == ST_PUBLISH);

    assign error_valid = (state == ST_ERROR);

    assign error_code = error_code_reg;
    assign event_order_id = order_id_reg;
    assign event_new_order_id = new_order_id_reg;
    assign event_side = side_reg;
    assign event_price = price_reg;
    assign event_quantity = quantity_reg;

    // Map NASDAQ Stock Locate to internal symbol index
    always_comb begin
        case (stock_locate_reg)
            LOCATE_0: event_symbol = 8'd0;
            LOCATE_1: event_symbol = 8'd1;
            LOCATE_2: event_symbol = 8'd2;
            LOCATE_3: event_symbol = 8'd3;
            default:  event_symbol = 8'hFF;
        endcase
    end

////////////////////////////// Status END

////////////////////////////// FSM BEGIN

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;

            message_type_reg    <= '0;
            byte_count_reg      <= '0;
            expected_length_reg <= '0;

            event_operation <= OP_INVALID;

            error_code_reg <= ERR_NONE;
        end
        else begin
            case(state) 
                ST_IDLE: begin
                    if (byte_valid && byte_read) begin
                        // accept byte 0
                        message_type_reg <= data_in;
                        byte_count_reg <= 8'd1;

                        // clear fields from the previous message
                        stock_locate_reg <= '0;
                        order_id_reg     <= '0;
                        new_order_id_reg <= '0;
                        side_reg         <= 1'b0;
                        quantity_reg     <= '0;
                        price_reg        <= '0;

                        event_operation <= OP_INVALID;

                        error_code_reg <= ERR_NONE;

                        // determine the length of this message
                        case (data_in)
                            MSG_ADD: begin
                                expected_length_reg <= LENGTH_ADD;
                                event_operation <= OP_ADD;
                                state <= ST_COLLECT;
                            end 

                            // Identical with MSG_ADD for now
                            MSG_ADD_MPID: begin
                                expected_length_reg <= LENGTH_ADD_MPID;
                                event_operation <= OP_ADD;
                                state <= ST_COLLECT;
                            end

                            MSG_CANCEL: begin
                                expected_length_reg <= LENGTH_CANCEL;
                                event_operation <= OP_REDUCE;
                                state <= ST_COLLECT;
                            end

                            MSG_EXECUTE: begin
                                expected_length_reg <= LENGTH_EXECUTE;
                                event_operation <= OP_REDUCE;
                                state <= ST_COLLECT;
                            end

                            MSG_EXECUTE_PRICE: begin
                                expected_length_reg <= LENGTH_EXECUTE_PRICE;
                                event_operation <= OP_REDUCE;
                                state <= ST_COLLECT;
                            end

                            MSG_DELETE: begin
                                expected_length_reg <= LENGTH_DELETE;
                                event_operation <= OP_DELETE;
                                state <= ST_COLLECT;
                            end

                            MSG_REPLACE: begin
                                expected_length_reg <= LENGTH_REPLACE;
                                event_operation <= OP_REPLACE;
                                state <= ST_COLLECT;
                            end

                            default: begin
                                expected_length_reg <= '0;

                                error_code_reg <= ERR_UNSUPPORTED_MESSGAE;

                                state <= ST_ERROR;
                            end
                        endcase
                    end
                end

                ST_COLLECT: begin
                    if(byte_valid && byte_read) begin

                        case(message_type_reg) 
                            // A - ADD OPERATION
                            MSG_ADD: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // Side - byte 19
                                else if (byte_count_reg == 8'd19) begin
                                    side_reg <= (data_in == "S");
                                end

                                // Quantity: bytes 20-23
                                else if (byte_count_reg >= 8'd20 && byte_count_reg <= 8'd23) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end

                                // Price: bytes 32-35
                                else if (byte_count_reg >= 8'd32 && byte_count_reg <= 8'd35) begin
                                    price_reg <= {price_reg[23:0], data_in};
                                end    
                            end
                            
                            // F - ADD ORDER WITH MPID
                            MSG_ADD_MPID: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // Side - byte 19
                                else if (byte_count_reg == 8'd19) begin
                                    side_reg <= (data_in == "S");
                                end

                                // Quantity: bytes 20-23
                                else if (byte_count_reg >= 8'd20 && byte_count_reg <= 8'd23) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end

                                // Price: bytes 32-35
                                else if (byte_count_reg >= 8'd32 && byte_count_reg <= 8'd35) begin
                                    price_reg <= {price_reg[23:0], data_in};
                                end
                                
                                // Bytes 36-39 are MPID, ignore for now
                            end

                            // X - ORDER CANCEL
                            MSG_CANCEL: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // Cancelled quantity: bytes 19-22
                                else if (byte_count_reg >= 8'd19 && byte_count_reg <= 8'd22) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end
                            end

                            // E - ORDER EXECUTED
                            MSG_EXECUTE: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // Executed quantity: bytes 19-22
                                else if (byte_count_reg >= 8'd19 && byte_count_reg <= 8'd22) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end

                                // Bytes 23-30 are Match Number
                                // Ignore for order-book maintenance
                            end
                            
                            // C - ORDER EXECUTED WITH PRICE
                            MSG_EXECUTE_PRICE: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // Executed quantity: bytes 19-22
                                else if (byte_count_reg >= 8'd19 && byte_count_reg <= 8'd22) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end

                                // Bytes 23-30 are Match Number
                                // Ignore for order-book maintenance
                            end
                            
                            // D - DELETE ORDER
                            MSG_DELETE: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end
                            end
                            
                            // U - ORDER REPLACE
                            MSG_REPLACE: begin
                                // Stock Locate: bytes 1-2
                                if (byte_count_reg >= 8'd1 && byte_count_reg <= 8'd2) begin
                                    stock_locate_reg <= {stock_locate_reg[7:0], data_in};
                                end

                                // Order ID: bytes 11-18
                                else if (byte_count_reg >= 8'd11 && byte_count_reg <= 8'd18) begin
                                    order_id_reg <= {order_id_reg[55:0], data_in};
                                end

                                // New Order ID: bytes 19-26
                                else if (byte_count_reg >= 8'd19 && byte_count_reg <= 8'd26) begin
                                    new_order_id_reg <= {new_order_id_reg[55:0], data_in};
                                end

                                // New Quantity: bytes 27-30
                                else if (byte_count_reg >= 8'd27 && byte_count_reg <= 8'd30) begin
                                    quantity_reg <= {quantity_reg[23:0], data_in};
                                end

                                // New Price: bytes 31-34
                                else if (byte_count_reg >= 8'd31 && byte_count_reg <= 8'd34) begin
                                    price_reg <= {price_reg[23:0], data_in};
                                end
                            end
                            
                            default: begin
                                // Unsupported messages should never
                                // reach ST_COLLECT
                            end

                        endcase

                        // Counting accepted bytes
                        if (byte_count_reg == expected_length_reg - 1'b1)
                            state <= ST_PUBLISH;

                        else begin
                            byte_count_reg <= byte_count_reg + 1'b1;                   
                        end
                    end
                end

                ST_PUBLISH: begin
                    if (event_ready) begin
                        state <= ST_IDLE;
                    end
                end
                
                ST_ERROR: begin
                    // stay in the same state until reset
                    state <= ST_ERROR;
                end

                default: begin
                    error_code_reg <= ERR_INVALID_STATE;
                    state <= ST_ERROR;
                end
            endcase
        end
    end

endmodule