/*  Unlike order_store, order_level has its own memory to keep track of the overall quantity at a specific price level
    which is nice the strategy module can make decisions based on the current looking of the market stored in this BRAM.
    Order_store is a place that we track of the status of all the active orders using 3 BRAMs; here, we use only one BRAM 
    to store all the price levels, and registers for the best bid/ask. The reason why we're storing the best bid/ask
    in registers but not in the BRAM is because we want instant access whenever the strategy module needs the info, storing 
    them in the BRAM introduces extra latency, which is not ideal for a system that requires the lowest latency possible.

    The order_level module has two main responsibilities:
        1. Maintain the order-level BRAM(source of truth)
        Store and update the total quantity and order count for every active
        {symbol, side, price} level.

        2. Maintain the best bid/ask registers 
        Store the best bid level and best ask level for each symbol,
        allowing the strategy module to access them immediately and in parallel.
        Note: the registers must update after the BRAM updates.

    Therefore, this module mainly maintains the following logic:
    (this might not be a comprehensive list of all the logics implemented in this module, 
                                                I wrote it down just to help me get started..)    
        1. Accept an order-level update from order_store using a valid/ready handshake.
        2. Locate the corresponding price-level entry using XOR{symbol, side, price}, same thing was used in order_store.
        3. Decode the signed quantity and order-count update from order_store.
        4. Update the total quantity and order count stored at the price level.
        5. Create a new price-level entry when an Add introduces a price that does not already exist.
        6. Update the best bid when a higher bid price arrives.
        7. Update the best ask when a lower ask price arrives.

    Flow: Incoming order_level change -> Read current BRAM level -> Wait for read -> Capture BRAM data
          update quantity/count -> Write updated level to BRAM -> update best bid/ask registers -> Done

    Note: when the current best level is completely removed, the best register becomes invalid.
          Finding the next-best level from BRAM can be implemented later.
          The strategy module must check best_bid_valid and best_ask_valid before using the data.
*/


module order_level_p3 #(
    parameter int NUM_SYMBOLS = 4,
    parameter int NUM_PROBES = 3,

    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 32,
    parameter int COUNT_WIDTH = 16,
    
    parameter int TABLE_DEPTH = 128,
    parameter int ADDR_WIDTH = $clog2(TABLE_DEPTH),
    parameter int ENTRY_WIDTH = 8 + 1 + PRICE_WIDTH + QUANTITY_WIDTH + COUNT_WIDTH + 7
)(
    input logic clk,
    input logic rst,
    
    // update from order_store
    input  logic                     order_level_valid,
    output logic                     order_level_ready,

    input  logic [7:0]               order_level_symbol,
    input  logic                     order_level_side,
    input  logic [PRICE_WIDTH-1:0]   order_level_price,
    input  logic signed [QUANTITY_WIDTH:0] order_level_quantity,
    input  logic signed [1:0]        order_level_order_count,

    // BRAM Interface
    input logic [ENTRY_WIDTH-1:0]   read_data,

    output logic                    read_en,
    output logic [ADDR_WIDTH-1:0]   read_addr,

    output logic                    write_en,
    output logic [ADDR_WIDTH-1:0]   write_addr,
    output logic [ENTRY_WIDTH-1:0]  write_data,

    // best bid
    output logic [PRICE_WIDTH-1:0] best_bid_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0] best_bid_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0] best_bid_order_count [0:NUM_SYMBOLS-1],
    output logic best_bid_valid [0:NUM_SYMBOLS-1],

    // best ask
    output logic [PRICE_WIDTH-1:0] best_ask_price [0:NUM_SYMBOLS-1],
    output logic [QUANTITY_WIDTH-1:0] best_ask_quantity [0:NUM_SYMBOLS-1],
    output logic [COUNT_WIDTH-1:0] best_ask_order_count [0:NUM_SYMBOLS-1],
    output logic best_ask_valid [0:NUM_SYMBOLS-1],

    // status
    output logic operation_done,
    output logic error_valid,
    output logic [3:0] error_code
);

    localparam int PROBE_INDEX_WIDTH = $clog2(NUM_PROBES);
    localparam int SYMBOL_INDEX_WIDTH = $clog2(NUM_SYMBOLS);

    localparam logic [QUANTITY_WIDTH-1:0] MAX_QUANTITY = '1;
    localparam logic [COUNT_WIDTH-1:0] MAX_ORDER_COUNT = '1;

    localparam logic [PROBE_INDEX_WIDTH-1:0] LAST_PROBE_INDEX =
        PROBE_INDEX_WIDTH'(NUM_PROBES - 1);

    localparam logic [7:0] NUM_SYMBOLS_LIMIT =
        8'(NUM_SYMBOLS);


    //structure decelation
    typedef struct packed {
        logic [7:0]                    symbol;
        logic                          side;
        logic [PRICE_WIDTH-1:0]        price;
        logic [QUANTITY_WIDTH-1:0]     total_quantity;
        logic [COUNT_WIDTH-1:0]        order_count;
        logic [6:0]                    padding;

    } order_level_entry_t;

    // FSM states
    typedef enum logic[3:0] { 
        ST_IDLE,
        ST_READ_REQUEST,
        ST_WAIT_FOR_READ,
        ST_CAPTURE_READ,
        ST_CHECK,
        ST_PROBE_DONE,
        ST_MODIFY,
        ST_WRITE,
        ST_UPDATE_BEST,
        ST_DONE
    } order_level_state_t;
    order_level_state_t state;

    // error codes
    typedef enum logic[3:0] { 
        ERR_NONE,
        ERR_LEVEL_NOT_FOUND,
        ERR_LEVEL_TABLE_FULL,
        ERR_QUANTITY_TOO_LARGE,
        ERR_QUANTITY_OVERFLOW,
        ERR_ORDER_COUNT_UNDERFLOW,
        ERR_ORDER_COUNT_OVERFLOW,
        ERR_INCONSISTENT_LEVEL,
        ERR_INVALID_UPDATE,
        ERR_INVALID_SYMBOL,
        ERR_INVALID_STATE
    } order_level_error_t;

    order_level_error_t error_code_reg;
    assign error_code = error_code_reg;
    assign error_valid = (state == ST_DONE) && (error_code_reg != ERR_NONE);

    // opreation decode
    typedef enum logic [1:0] {
        LEVEL_ADD_ORDER,
        LEVEL_REDUCE_QUANTITY,
        LEVEL_REMOVE_ORDER
    } level_operation_t;

    level_operation_t operation_reg;
   
    // Registers for incoming update
    logic [7:0]                 symbol_reg;
    logic                       side_reg;
    logic [PRICE_WIDTH-1:0]     price_reg;
    logic [QUANTITY_WIDTH-1:0]  quantity_reg;

    // BRAM lookup and probing
    logic [ADDR_WIDTH-1:0] read_addr_reg;
    logic [ADDR_WIDTH-1:0] write_addr_reg;
    logic [PROBE_INDEX_WIDTH-1:0] probe_index_reg;
    logic first_empty_found_reg;
    logic [ADDR_WIDTH-1:0] first_empty_addr_reg;
    logic current_entry_valid_reg, level_found_reg;

    // BRAM entry data
    order_level_entry_t current_entry_reg, next_entry_reg;
    logic next_entry_valid_reg;

    //Seperate valid_bit table for the small prototype
    logic [TABLE_DEPTH-1:0] level_valid_bits_bram;

    logic [SYMBOL_INDEX_WIDTH-1:0] symbol_index;

    assign symbol_index = symbol_reg[SYMBOL_INDEX_WIDTH-1:0];

    // when the best level is removed, the cached value cannot be trusted
    logic best_bid_rebuild_required [0:NUM_SYMBOLS-1];
    logic best_ask_rebuild_required [0:NUM_SYMBOLS-1];

    // status
    assign order_level_ready = (state == ST_IDLE);
    assign operation_done = (state == ST_DONE);
    assign read_addr = read_addr_reg;
    assign write_addr = write_addr_reg;
    assign write_data = next_entry_reg;

    // hash function 
    // consider the size of the entries, here we're going to use 
    // sequential probe to handle the collision cases(not three bank)
    // using this method will add latency to system
    // but it will only introduce latency to the write path
    // not the read path for strategy module to read
    function automatic logic [ADDR_WIDTH-1:0] hash_order_level(
        input logic [7:0] symbol, input logic side, 
        input logic [PRICE_WIDTH-1:0] price
    );

    logic [41:0] padded_key;

    begin 
        // original key is 41 bits: {symbol, side, price}
        // add one zero to make it 42 bits, which can be divided into six 7-bit chunks

        padded_key = {1'b0, symbol, side, price};

        hash_order_level = padded_key[6:0]
                        ^ padded_key[13:7]
                        ^ padded_key[20:14]
                        ^ padded_key[27:21]
                        ^ padded_key[34:28]
                        ^ padded_key[41:35];
    end
    endfunction

// FSM
always_ff @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;

        operation_reg <= LEVEL_ADD_ORDER;

        symbol_reg <= '0;
        side_reg <= 1'b0;
        price_reg <= '0;
        quantity_reg <= '0;

        read_addr_reg <= '0;
        write_addr_reg <= '0;
        probe_index_reg <= '0;

        first_empty_found_reg <= 1'b0;
        first_empty_addr_reg <= '0;

        current_entry_valid_reg <= 1'b0;
        level_found_reg <= 1'b0;

        current_entry_reg <= '0;
        next_entry_reg <= '0;
        next_entry_valid_reg <= 1'b0;

        level_valid_bits_bram <= '0;

        read_en <= 1'b0;
        write_en <= 1'b0;

        error_code_reg <= ERR_NONE;

        for (int symbol_index_i = 0; symbol_index_i < NUM_SYMBOLS; symbol_index_i++) begin
            best_bid_price[symbol_index_i] <= '0;
            best_bid_quantity[symbol_index_i] <= '0;
            best_bid_order_count[symbol_index_i] <= '0;
            best_bid_valid[symbol_index_i] <= 1'b0;
            best_bid_rebuild_required[symbol_index_i] <= 1'b0;

            best_ask_price[symbol_index_i] <= '0;
            best_ask_quantity[symbol_index_i] <= '0;
            best_ask_order_count[symbol_index_i] <= '0;
            best_ask_valid[symbol_index_i] <= 1'b0;
            best_ask_rebuild_required[symbol_index_i] <= 1'b0;
        end
    end

    else begin
        read_en <= 1'b0;
        write_en <= 1'b0;

        case(state)

            // store the incoming change to registers
            // signed values from order_store are decoded here
            ST_IDLE: begin
                if(order_level_valid && order_level_ready) begin
                    symbol_reg <= order_level_symbol;
                    side_reg <= order_level_side;
                    price_reg <= order_level_price;

                    probe_index_reg <= '0;

                    first_empty_found_reg <= 1'b0;
                    first_empty_addr_reg <= '0;

                    current_entry_valid_reg <= 1'b0;
                    level_found_reg <= 1'b0;

                    current_entry_reg <= '0;
                    next_entry_reg <= '0;
                    next_entry_valid_reg <= 1'b0;

                    error_code_reg <= ERR_NONE;

                    if(order_level_symbol >= NUM_SYMBOLS_LIMIT) begin
                        error_code_reg <= ERR_INVALID_SYMBOL;
                        state <= ST_DONE;
                    end

                    // add a new order
                    else if(order_level_quantity > 0 && order_level_order_count == 2'sd1) begin
                        operation_reg <= LEVEL_ADD_ORDER;
                        quantity_reg <= QUANTITY_WIDTH'(order_level_quantity);

                        read_addr_reg <= hash_order_level(
                            order_level_symbol,
                            order_level_side,
                            order_level_price
                        );

                        state <= ST_READ_REQUEST;
                    end

                    // reduce quantity but keep the order active
                    else if(order_level_quantity < 0 && order_level_order_count == 2'sd0) begin
                        operation_reg <= LEVEL_REDUCE_QUANTITY;

                        // convert the sign so it's easier to deal with in modify state
                        quantity_reg <= QUANTITY_WIDTH'(-order_level_quantity);

                        read_addr_reg <= hash_order_level(
                            order_level_symbol,
                            order_level_side,
                            order_level_price
                        );

                        state <= ST_READ_REQUEST;
                    end

                    // remove one complete order
                    else if(order_level_quantity < 0 && order_level_order_count == -2'sd1) begin
                        operation_reg <= LEVEL_REMOVE_ORDER;

                        // convert the sign so it's easier to deal with in modify state
                        quantity_reg <= QUANTITY_WIDTH'(-order_level_quantity);

                        read_addr_reg <= hash_order_level(
                            order_level_symbol,
                            order_level_side,
                            order_level_price
                        );

                        state <= ST_READ_REQUEST;
                    end

                    else begin
                        error_code_reg <= ERR_INVALID_UPDATE;
                        state <= ST_DONE;
                    end
                end
            end
            
            ST_READ_REQUEST: begin
                read_en <= 1'b1;
                state <= ST_WAIT_FOR_READ;
            end

            ST_WAIT_FOR_READ: begin
                state <= ST_CAPTURE_READ;
            end

            ST_CAPTURE_READ: begin
                current_entry_reg <= order_level_entry_t'(read_data);
                current_entry_valid_reg <= level_valid_bits_bram[read_addr_reg];
                    
                state <= ST_CHECK;
            end

            ST_CHECK: begin
            // three questions for check state:
            //  does this current entry match?
            //  is this current entry empty?
            //  are there more probes left?      

                // Current BRAM entry matches the requested level
                if (current_entry_valid_reg && current_entry_reg.symbol == symbol_reg
                    && current_entry_reg.side == side_reg 
                    && current_entry_reg.price == price_reg) begin

                        write_addr_reg <= read_addr_reg;
                        level_found_reg <= 1'b1;
                        
                        state <= ST_MODIFY;
                    end

                // did not match
                else begin

                    // remember the first empty probe locaiton
                    if (!current_entry_valid_reg && !first_empty_found_reg) begin
                        first_empty_found_reg <= 1'b1;
                        first_empty_addr_reg <= read_addr_reg;
                    end

                    // check if all the probe locations have been checked
                    if (probe_index_reg == LAST_PROBE_INDEX) begin
                        state <= ST_PROBE_DONE;
                    end

                    // move to the next sequential probe
                    else begin
                        probe_index_reg <= probe_index_reg + 1'b1;
                        read_addr_reg <= read_addr_reg + 1'b1;

                        state <= ST_READ_REQUEST;
                    end

                end
            end
            
            ST_PROBE_DONE: begin
            // question: what should we do if no matching level exists after checking every probe    

                // A new order can create a missing price level
                if (operation_reg == LEVEL_ADD_ORDER) begin
                    if(first_empty_found_reg) begin
                        write_addr_reg <= first_empty_addr_reg;
                        current_entry_reg <= '0;
                        level_found_reg <= 1'b0;

                        state <= ST_MODIFY;
                    end

                    else begin
                        error_code_reg <= ERR_LEVEL_TABLE_FULL;
                        state <= ST_DONE;
                    end
                end

                else begin
                    // reduce/delete/execute expected the level to already exist 
                    error_code_reg <= ERR_LEVEL_NOT_FOUND;
                    state <= ST_DONE;
                end
            end

            ST_MODIFY: begin
                case(operation_reg)

                    LEVEL_ADD_ORDER: begin

                        // add to an existing price level
                        if(level_found_reg) begin
                            if(current_entry_reg.total_quantity > MAX_QUANTITY - quantity_reg) begin
                                error_code_reg <= ERR_QUANTITY_OVERFLOW;
                                state <= ST_DONE;
                            end

                            else if(current_entry_reg.order_count == MAX_ORDER_COUNT) begin
                                error_code_reg <= ERR_ORDER_COUNT_OVERFLOW;
                                state <= ST_DONE;
                            end

                            else begin
                                next_entry_reg <= current_entry_reg;

                                next_entry_reg.total_quantity <=
                                    current_entry_reg.total_quantity + quantity_reg;

                                next_entry_reg.order_count <=
                                    current_entry_reg.order_count + 1'b1;

                                next_entry_valid_reg <= 1'b1;
                                state <= ST_WRITE;
                            end
                        end

                        // create a new price level
                        else begin
                            next_entry_reg.symbol <= symbol_reg;
                            next_entry_reg.side <= side_reg;
                            next_entry_reg.price <= price_reg;
                            next_entry_reg.total_quantity <= quantity_reg;
                            next_entry_reg.order_count <= 1;
                            next_entry_reg.padding <= '0;

                            next_entry_valid_reg <= 1'b1;
                            state <= ST_WRITE;
                        end
                    end

                    LEVEL_REDUCE_QUANTITY: begin
                        if(!level_found_reg) begin
                            error_code_reg <= ERR_LEVEL_NOT_FOUND;
                            state <= ST_DONE;
                        end

                        // partial reduction must leave some quantity
                        else if(quantity_reg >= current_entry_reg.total_quantity) begin
                            error_code_reg <= ERR_QUANTITY_TOO_LARGE;
                            state <= ST_DONE;
                        end

                        else begin
                            next_entry_reg <= current_entry_reg;

                            next_entry_reg.total_quantity <=
                                current_entry_reg.total_quantity - quantity_reg;

                            next_entry_valid_reg <= 1'b1;
                            state <= ST_WRITE;
                        end
                    end

                    LEVEL_REMOVE_ORDER: begin
                        if(!level_found_reg) begin
                            error_code_reg <= ERR_LEVEL_NOT_FOUND;
                            state <= ST_DONE;
                        end

                        else if(quantity_reg > current_entry_reg.total_quantity) begin
                            error_code_reg <= ERR_QUANTITY_TOO_LARGE;
                            state <= ST_DONE;
                        end

                        // remove the entire level if this is the final order
                        else if(current_entry_reg.order_count == 1) begin
                            if(quantity_reg != current_entry_reg.total_quantity) begin
                                error_code_reg <= ERR_INCONSISTENT_LEVEL;
                                state <= ST_DONE;
                            end

                            else begin
                                next_entry_reg <= '0;
                                next_entry_valid_reg <= 1'b0;

                                state <= ST_WRITE;
                            end
                            
                        end

                        else if(quantity_reg == current_entry_reg.total_quantity) begin
                            error_code_reg <= ERR_INCONSISTENT_LEVEL;
                            state <= ST_DONE;
                        end

                        // subtract the removed order from the price level
                        else begin
                            next_entry_reg <= current_entry_reg;

                            next_entry_reg.total_quantity <=
                                current_entry_reg.total_quantity - quantity_reg;

                            next_entry_reg.order_count <=
                                current_entry_reg.order_count - 1'b1;

                            next_entry_valid_reg <= 1'b1;
                            state <= ST_WRITE;
                        end
                    end

                    default: begin
                        error_code_reg <= ERR_INVALID_UPDATE;
                        state <= ST_DONE;
                    end

                endcase
            end

            ST_WRITE: begin
                write_en <= 1'b1;

                level_valid_bits_bram[write_addr_reg] <= next_entry_valid_reg;

                state <= ST_UPDATE_BEST;
            end

            ST_UPDATE_BEST: begin
                // update best bid
                if(!side_reg) begin

                    // this level is already the best bid
                    if(best_bid_valid[symbol_index]
                        && best_bid_price[symbol_index] == price_reg) begin

                        // level still exists
                        if(next_entry_valid_reg) begin
                            best_bid_quantity[symbol_index] <= next_entry_reg.total_quantity;
                            best_bid_order_count[symbol_index] <= next_entry_reg.order_count;
                        end

                        // best bid level was removed
                        else begin
                            best_bid_price[symbol_index] <= '0;
                            best_bid_quantity[symbol_index] <= '0;
                            best_bid_order_count[symbol_index] <= '0;
                            best_bid_valid[symbol_index] <= 1'b0;
                            best_bid_rebuild_required[symbol_index] <= 1'b1;
                        end
                    end

                    // new price level is better than the current best bid
                    else if(!best_bid_rebuild_required[symbol_index]
                        && !level_found_reg && next_entry_valid_reg
                        && (!best_bid_valid[symbol_index]
                        || price_reg > best_bid_price[symbol_index])) begin

                        best_bid_price[symbol_index] <= next_entry_reg.price;
                        best_bid_quantity[symbol_index] <= next_entry_reg.total_quantity;
                        best_bid_order_count[symbol_index] <= next_entry_reg.order_count;
                        best_bid_valid[symbol_index] <= 1'b1;
                        best_bid_rebuild_required[symbol_index] <= 1'b0;
                    end
                end

                // update best ask
                else begin

                    // this level is already the best ask
                    if(best_ask_valid[symbol_index]
                        && best_ask_price[symbol_index] == price_reg) begin

                        // level still exists
                        if(next_entry_valid_reg) begin
                            best_ask_quantity[symbol_index] <= next_entry_reg.total_quantity;
                            best_ask_order_count[symbol_index] <= next_entry_reg.order_count;
                        end

                        // best ask level was removed
                        else begin
                            best_ask_price[symbol_index] <= '0;
                            best_ask_quantity[symbol_index] <= '0;
                            best_ask_order_count[symbol_index] <= '0;
                            best_ask_valid[symbol_index] <= 1'b0;
                            best_ask_rebuild_required[symbol_index] <= 1'b1;
                        end
                    end

                    // new price level is better than the current best ask
                    else if(!best_ask_rebuild_required[symbol_index]
                        && !level_found_reg && next_entry_valid_reg
                        && (!best_ask_valid[symbol_index]
                        || price_reg < best_ask_price[symbol_index])) begin

                        best_ask_price[symbol_index] <= next_entry_reg.price;
                        best_ask_quantity[symbol_index] <= next_entry_reg.total_quantity;
                        best_ask_order_count[symbol_index] <= next_entry_reg.order_count;
                        best_ask_valid[symbol_index] <= 1'b1;
                        best_ask_rebuild_required[symbol_index] <= 1'b0;
                    end
                end

                state <= ST_DONE;
            end

            ST_DONE: begin
                state <= ST_IDLE;
            end

            default: begin
                error_code_reg <= ERR_INVALID_STATE;
                state <= ST_DONE;
            end

        endcase
    end
end

endmodule