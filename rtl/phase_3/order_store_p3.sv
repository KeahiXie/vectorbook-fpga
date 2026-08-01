/*
In this new version of the order book, it's no longer a snapshot 
of what's being feed into our pipeline. In this phase, we're implementing 
an order book supports Nasdap ITCH5.0 protocol to provide a current state of 
the market. This order book supports Add, Cancel, Delete Order and etc.

when building this order book, we will explicitly use BRAM to store everything.
The address of each order in the BRAM will be created by a hash table by order_id, 
so that we can reduce the latency when fetching an order(no searching invovled). we plan to use a 
a bounded hash table to avoid collisions instead of other methods.

hash table doesn't gurantee there will be no more collisions.

Using BRAM introduce an extra cycle here: 
request a read during one clock cyle -> getting data the next cycle

Therefore, order_book will be built based on a FSM that has the following states:
IDLE -> READ_ORDER -> WAIT_FOR_READ -> MOFIDY_ORDER -> WRITE_ORDER -> COMPLETE

A SYNC FIFO we built in phase 2 will be modified and used here, because we want 
the order book has no stall(new event) when the current order is not completed

OUTPUT:
Order_level: each order from NASDAQ
Per-symbol info: 
total order numbers on bid/ask
top 10 price level on each side with 
top 10 price level on each side with

Cycles for Replace: IDLE -> READ_REQUEST -> WAIT_FOR_READ -> CHECK -> MODIFY(phase0)
        (13 cycles) READ_REQUEST -> WAIT_FOR_READ -> CHECK -> MODIFY(phase1) ->
                    ORDER_LEVEL → WRITE → ORDER_LEVEL → DONE







1. Message type: Add
input: order_id, symbol, side, price, quantity
Operation: 
    a. calculate address from order_id
    b. check the address on BRAM add the quantity if it exists
    c. store the complete order
    d. mark valid = 1
    e. update the best bid/ask if necessary

2. Message type: Delete
input: order_id, cancel_quantity
Operation:
    a. clacualte address from order_id
    b. return error if not exist 
    c. subtract cancel_quantity, invalidate the order if less than zero

3. Message type: Execute Order
input: order_id
Operation:
    a. find order
    b. return error if not exist 
    c. subtract cancel_quantity, invalidate the order if less than zero
    


*/

/*

type 
always_ff (@posedge clk) begin

end

*/


module order_store_p3 #(
    parameter int NUM_BANKS   = 3,
    parameter int TABLE_DEPTH = 128,
    parameter int ADDR_WIDTH  = $clog2(TABLE_DEPTH),
    parameter int ENTRY_WIDTH = 144
) (
    input logic clk,
    input logic rst,

    // Incoming normalized order event
    input logic                    event_valid,
    output logic                   event_ready,

    input logic [2:0]              event_operation,
    input logic [63:0]             event_order_id,
    input logic [63:0]              event_new_order_id,
    input logic [7:0]              event_symbol,
    input logic                       event_side,
    input logic [31:0]             event_price,
    input logic [31:0]             event_quantity,

    // BRAM read interface
    input logic [ENTRY_WIDTH-1:0]  read_data [0:NUM_BANKS-1],
    input logic                    read_valid,

    output logic [ADDR_WIDTH-1:0]  read_addr,
    output logic [NUM_BANKS-1:0]   read_en,

    // BRAM write interface
    output logic [ENTRY_WIDTH-1:0] write_data [0:NUM_BANKS-1],
    output logic [ADDR_WIDTH-1:0]  write_addr,
    output logic [NUM_BANKS-1:0]   write_en,

    // Operation result
    output logic                   operation_done,
    output logic                   error_valid,
    output logic [3:0]             error_code,


    // ORDER_LEVEL update interface
    output  logic order_level_valid,
    input   logic order_level_ready,

    output  logic [7:0] order_level_symbol,
    output  logic order_level_side,
    output  logic[31:0] order_level_price,
    output  logic signed[32:0] order_level_quantity,
    output  logic signed [1:0] order_level_order_count


);

    localparam int BANK_INDEX_WIDTH = $clog2(NUM_BANKS);

    // hash function definition
    function automatic logic [ADDR_WIDTH-1:0] hash_order_id(
        input logic [63:0] order_id
    );
    
    // Table depth is 128 so address width is 7
    // we use a simple XOR here to generate a unique result for each order_id
    // since the input is 64 bits, we need to pad it to 70 bits
    // so we can XOR ten times
    logic [69:0] padded_id;
    begin
        padded_id = {6'b0, order_id};
        hash_order_id = 
                padded_id[6:0]
                ^ padded_id[13:7]
                ^ padded_id[20:14]
                ^ padded_id[27:21]
                ^ padded_id[34:28]
                ^ padded_id[41:35]
                ^ padded_id[48:42]
                ^ padded_id[55:49]
                ^ padded_id[62:56]
                ^ padded_id[69:63];            
    end

    endfunction



    //-----------------------------------
    //------Structure Defintion----------

    // order_reg
    typedef struct packed {
        logic [63:0] order_id;
        logic [7:0]  symbol;
        logic        side;
        logic [31:0] price;
        logic [31:0] quantity;
        logic [6:0]  padding;
    } order_entry_t;

    logic[63:0] order_id_reg; 
    logic[63:0] new_order_id_reg; // replacement id from the parser
    logic[7:0] symbol_reg;
    logic side_reg;
    logic[31:0] price_reg;
    logic[31:0] quantity_reg;

    order_entry_t replace_old_entry_reg; // saves old data for old entry
    logic [ADDR_WIDTH-1:0] replace_old_addr_reg; // remember where the old order lives
    logic [BANK_INDEX_WIDTH-1:0] replace_old_bank_reg; // remember which bank holds the old order
    logic [BANK_INDEX_WIDTH-1:0] replace_new_bank_reg; // remembers where the replacement will be written

    logic replace_phase_reg; // 0 for looking up the old order and 1 for the new order


    
    // opreation
    typedef enum logic [2:0] {
        OP_ADD,
        OP_REDUCE,
        OP_DELETE,
        OP_REPLACE,
        OP_INVALID
    } operation_t;
    operation_t op_reg;

    // state
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_READ_REQUEST,
        ST_WAIT_FOR_READ,
        ST_CHECK,
        ST_MODIFY,
        ST_WRITE,
        ST_ORDER_LEVEL,
        ST_DONE
    } state_t;
    state_t state;
    
    // error code
    typedef enum logic [3:0] {
    ERR_NONE                = 4'h0,
    ERR_INVALID_OPERATION   = 4'h1,
    ERR_ORDER_NOT_FOUND     = 4'h2,
    ERR_DUPLICATE_ORDER     = 4'h3,
    ERR_BUCKET_FULL         = 4'h4,
    ERR_QUANTITY_TOO_LARGE  = 4'h5,
    ERR_ZERO_QUANTITY       = 4'h6,
    ERR_INVALID_STATE            = 4'hF
    } error_code_t;
    error_code_t error_code_reg;
    assign error_code = error_code_reg;
    assign error_valid = (state == ST_DONE) && (error_code_reg != ERR_NONE);
    //------------------------------------
    //------------------------------------   
 



    //---------------------------------------------
    // Internal signals section 

    // current table address
    logic [ADDR_WIDTH-1:0] lookup_addr;
    assign write_addr = lookup_addr;
    assign read_addr = lookup_addr;
    assign event_ready = (state == ST_IDLE);
    assign operation_done = (state == ST_DONE);

    // BRAM entries
    order_entry_t bank_read_entry [0:NUM_BANKS-1];
    order_entry_t modified_entry;

    // Memory valid bits(not in BRAM)
    logic [TABLE_DEPTH-1:0] valid_bits [0:NUM_BANKS-1];

    // Lookup results
    logic match_found;
    logic empty_found;
    logic [NUM_BANKS-1: 0] empty_bank;
    logic [NUM_BANKS-1: 0] occupied_bank;
    logic [BANK_INDEX_WIDTH-1: 0] matching_bank;
    logic [BANK_INDEX_WIDTH-1: 0] write_selected_bank;

    // price level regs

    logic [7:0]        order_level_symbol_reg;
    logic               order_level_side_reg;
    logic [31:0]        order_level_price_reg;
    logic signed [32:0] order_level_quantity_reg;
    logic signed [1:0]  order_level_order_count_reg;
    assign order_level_valid = (state == ST_ORDER_LEVEL);
    

    assign order_level_symbol =  order_level_symbol_reg;
    assign order_level_side =  order_level_side_reg;      
    assign order_level_price = order_level_price_reg;
    assign order_level_quantity = order_level_quantity_reg;
    assign order_level_order_count = order_level_order_count_reg;
        
    //---------------------------------------------
    //---------------------------------------------
    
    




    //-----------------------------------------------------------
    // FSM Body
    always_ff @(posedge clk) begin
        if(rst) begin

            state <= ST_IDLE;

            // event_regs
            op_reg       <= OP_INVALID;
            order_id_reg <= '0;
            symbol_reg   <= '0;
            side_reg     <= 1'b0;
            price_reg    <= '0;
            quantity_reg <= '0; 

            // Address and bank-selection regsiters
            lookup_addr <= '0;
            matching_bank      <= '0;
            write_selected_bank <= '0;
            
            // Lookup-result registers
            occupied_bank <= '0;
            empty_bank    <= '0;
            empty_found   <= 1'b0;
            match_found   <= 1'b0;

            // Entry registers
            modified_entry <= '0;

            //clean up register array
            for (int i = 0; i < NUM_BANKS; i++) begin
                valid_bits[i]      <= '0;
                bank_read_entry[i] <= '0;
                write_data[i]      <= '0;
            end

            // BRAM control outputs
            read_en  <= '0;
            write_en <= '0;

            // Result outputs/registers
            error_code_reg <= ERR_NONE;

            // price level regs reset
            order_level_symbol_reg      <= '0;
            order_level_side_reg        <= 1'b0;
            order_level_price_reg       <= '0;
            order_level_quantity_reg    <= '0;
            order_level_order_count_reg <= '0;

            // registers for replace
            replace_old_entry_reg <= '0;
            replace_old_addr_reg  <= '0;
            replace_old_bank_reg  <= '0;
            replace_new_bank_reg  <= '0;
            new_order_id_reg <= '0;




        end

        else begin
            write_en <= '0;
            read_en <= '0;


            case(state)
                ST_IDLE: begin
                    if (event_valid && event_ready) begin
                        op_reg       <= operation_t'(event_operation);
                        order_id_reg <= event_order_id;
                        new_order_id_reg <= event_new_order_id;
                        symbol_reg   <= event_symbol;
                        side_reg     <= event_side;
                        price_reg    <= event_price;
                        quantity_reg <= event_quantity; 

                        replace_phase_reg <= 1'b0;

                        lookup_addr <= hash_order_id(event_order_id);

                        // Clear results from the previous lookup
                        occupied_bank     <= '0;
                        empty_bank        <= '0;
                        empty_found       <= 1'b0;
                        match_found       <= 1'b0;
                        matching_bank     <= '0;
                        write_selected_bank <= '0;

                        // Clear the previous operation result
                        error_code_reg <= ERR_NONE;

                        // clear the old values in order_level regs
                        order_level_symbol_reg      <= '0;
                        order_level_side_reg        <= 1'b0;
                        order_level_price_reg       <= '0;
                        order_level_quantity_reg    <= '0;
                        order_level_order_count_reg <= '0;


                        state <= ST_READ_REQUEST;
                    end

                    
                end

                ST_READ_REQUEST: begin
                    read_en <= 3'b111;
                    state <= ST_WAIT_FOR_READ;
                    
                    occupied_bank <= '0;
                    empty_bank    <= '0;
                    empty_found   <= 1'b0;
                    match_found   <= 1'b0;
                end

                ST_WAIT_FOR_READ: begin
                    if(read_valid) begin
                        for(int i = 0; i < NUM_BANKS; i++) begin
                            // transfer read data to temporary register
                            bank_read_entry[i] <= order_entry_t'(read_data[i]);

                            // check if the lookup address is empty for next state
                            if (valid_bits[i][lookup_addr]) begin
                                occupied_bank[i] <= 1'b1;
                                empty_bank[i] <= 1'b0;
                            end

                            else begin
                                empty_bank[i] <= 1'b1;
                                empty_found <= 1'b1;
                                occupied_bank[i] <= 1'b0;
                            end

                        end

                        state <= ST_CHECK;
                    end


                    
                end

                ST_CHECK: begin
                    // In this state, we need to check in this order:
                    // ADD: we only care if the address is empty 
                    // REMOVE: a. we need to know if the address is empty
                    //         b. if the order_id matches
                    //         c. if the quantity: >, ==, <
                    // Delete: a. if the address is empty
                    //         b. if the order_id matches
                    // And we need to check all three bank 



                    // Initialization
                    match_found   <= 1'b0;
                    matching_bank <= '0;
                    write_selected_bank <= '0;

                    // Find the first matching order
                    for (int i = 0; i < NUM_BANKS; i++) begin
                        if (occupied_bank[i]) begin
                            if (bank_read_entry[i].order_id == order_id_reg) begin
                                match_found   <= 1'b1;
                                matching_bank <= BANK_INDEX_WIDTH'(i);
                                break;
                            end
                        end
                    end

                    // Select the first empty bank for a possible Add
                    if (empty_found) begin
                        for (int i = 0; i < NUM_BANKS; i++) begin
                            if (empty_bank[i]) begin
                                write_selected_bank <= BANK_INDEX_WIDTH'(i);
                                break;
                            end
                        end
                    end

                    state <= ST_MODIFY;
                

                end

                ST_MODIFY: begin
                    case(op_reg)
                        OP_ADD: begin

                            if (match_found) begin
                                error_code_reg <= ERR_DUPLICATE_ORDER;
                                state <= ST_DONE;
                            end
                            // all banks are full
                            else if (!empty_found) begin
                                error_code_reg <= ERR_BUCKET_FULL;
                                state <= ST_DONE;
                            end
                            // quantity must be larger than 0 in add op
                            else if(quantity_reg == 0) begin
                                error_code_reg <= ERR_ZERO_QUANTITY;
                                state <= ST_DONE;
                            end

                            // No error found procee to next state
                            else begin
                                // update modified entry for write in order_store BRAM(main)
                                modified_entry.order_id <= order_id_reg;
                                modified_entry.symbol   <= symbol_reg;
                                modified_entry.side     <= side_reg;
                                modified_entry.price    <= price_reg;
                                modified_entry.quantity <= quantity_reg;
                                modified_entry.padding  <= '0;

                                // update order_level regs for order_level BRAM
                                order_level_symbol_reg <= symbol_reg;
                                order_level_side_reg   <= side_reg;
                                order_level_price_reg  <= price_reg;
                    
                                //quantity change = + new quantity
                                //order count change = +1
                                order_level_quantity_reg <= $signed({1'b0, quantity_reg});
                                order_level_order_count_reg <= 2'sd1;

                                state <= ST_WRITE;
                            end
                        end

                        OP_REDUCE: begin
                            // can find the order
                            if (!match_found) begin
                                error_code_reg <= ERR_ORDER_NOT_FOUND;
                                state <= ST_DONE;
                            end
                            // Zero quantity to delect, remain the same
                            else if (quantity_reg == 0) begin
                                error_code_reg <= ERR_ZERO_QUANTITY;
                                state <= ST_DONE;
                            end
                            // the number of orders we're delecting is larger than what we have
                            else if (quantity_reg > bank_read_entry[matching_bank].quantity) begin
                                error_code_reg <= ERR_QUANTITY_TOO_LARGE;
                                state <= ST_DONE;
                            end

                            // Full Reduce:
                            // if we're going to remove all we have in the BRAM
                            // then we will skip the WRITE state and mark the memory address is empty
                            else if (quantity_reg == bank_read_entry[matching_bank].quantity) begin
                                    valid_bits[matching_bank][lookup_addr] <= 1'b0;
                                    order_level_symbol_reg <= bank_read_entry[matching_bank].symbol;
                                    order_level_side_reg   <= bank_read_entry[matching_bank].side;
                                    order_level_price_reg  <= bank_read_entry[matching_bank].price;
                                    order_level_quantity_reg <= -$signed({1'b0, bank_read_entry[matching_bank].quantity});
                                    order_level_order_count_reg <= -2'sd1;

                                    // No write needed bc separate valid bit removes the order
                                    state <= ST_ORDER_LEVEL;
                            end

                            // adjust the quantity in the BRAM
                            else begin
                                write_selected_bank <= matching_bank;
                                modified_entry.order_id <= bank_read_entry[matching_bank].order_id;                                 
                                modified_entry.symbol <= bank_read_entry[matching_bank].symbol;
                                modified_entry.side <= bank_read_entry[matching_bank].side;
                                modified_entry.price <= bank_read_entry[matching_bank].price;
                                modified_entry.quantity <= bank_read_entry[matching_bank].quantity - quantity_reg;                              
                                modified_entry.padding <= bank_read_entry[matching_bank].padding;

                                order_level_symbol_reg <= bank_read_entry[matching_bank].symbol;
                                order_level_side_reg   <= bank_read_entry[matching_bank].side;
                                order_level_price_reg  <= bank_read_entry[matching_bank].price;
                                order_level_quantity_reg <= -$signed({1'b0, quantity_reg });
                                order_level_order_count_reg <= 2'sd0;

                                state <= ST_WRITE;
                            end
                                
                                

                        end

                        OP_DELETE: begin
                            if(!match_found) begin
                                error_code_reg <= ERR_ORDER_NOT_FOUND;
                                state <= ST_DONE;
                            end

                            // skip write state because we only need to adjust the table outside of BRAM
                            else begin
                                valid_bits[matching_bank][lookup_addr] <= 1'b0;

                                order_level_symbol_reg <= bank_read_entry[matching_bank].symbol;
                                order_level_side_reg   <= bank_read_entry[matching_bank].side;
                                order_level_price_reg  <= bank_read_entry[matching_bank].price;
                                order_level_quantity_reg <= -$signed({1'b0, bank_read_entry[matching_bank].quantity });
                                order_level_order_count_reg <= -2'sd1;

                                state <= ST_ORDER_LEVEL;
                            end
                        end

                        OP_REPLACE: begin
                            // Phase 0: first the old order
                            if(!replace_phase_reg) begin
                                if(!match_found) begin
                                    error_code_reg <= ERR_ORDER_NOT_FOUND;
                                    state <= ST_DONE;
                                end

                                else if (quantity_reg == 0) begin
                                    error_code_reg <= ERR_ZERO_QUANTITY;
                                    state <= ST_DONE;
                                end

                                else begin
                                    // saving the original order
                                    replace_old_entry_reg <= bank_read_entry[matching_bank];
                                    replace_old_addr_reg <= lookup_addr;
                                    replace_old_bank_reg <= matching_bank;

                                    // Begin the second look up using the new order ID
                                    order_id_reg <= new_order_id_reg;
                                    lookup_addr <= hash_order_id(new_order_id_reg);

                                    replace_phase_reg <= 1'b1;

                                    occupied_bank <= '0;
                                    empty_bank <= '0;
                                    empty_found <= 1'b0;
                                    match_found <= 1'b0;

                                    matching_bank <= '0;
                                    write_selected_bank <= '0;

                                    state <= ST_READ_REQUEST;



                                end
                            end

                            // Phase 1: fin the new order
                            else begin
                                // New order ID already exists
                                if (match_found) begin
                                    error_code_reg <= ERR_DUPLICATE_ORDER;
                                    state <= ST_DONE;
                                end

                                else if (!empty_found) begin
                                    error_code_reg <= ERR_BUCKET_FULL;
                                    state <= ST_DONE;
                                end

                                else begin
                                    // prepare the replacement order for write state
                                    modified_entry.order_id <= new_order_id_reg;
                                    modified_entry.symbol <= replace_old_entry_reg.symbol;
                                    modified_entry.side <= replace_old_entry_reg.side;
                                    modified_entry.price <= price_reg;
                                    modified_entry.quantity <= quantity_reg;
                                    modified_entry.padding <= '0;

                                    // first order_level update for removing the old order
                                    order_level_symbol_reg <= replace_old_entry_reg.symbol;
                                    order_level_side_reg <= replace_old_entry_reg.side;
                                    order_level_price_reg <= replace_old_entry_reg.price;
                                    order_level_quantity_reg <= -$signed({1'b0, replace_old_entry_reg.quantity});
                                    order_level_order_count_reg <= -2'sd1;
                                    
                                    state <= ST_ORDER_LEVEL;

                                end


                            end
                        end

                        default: begin
                            error_code_reg <= ERR_INVALID_OPERATION;
                            state <= ST_DONE;
                        end
                    
                    endcase
                    
                end

                ST_WRITE: begin

                    write_en[write_selected_bank] <= 1'b1;
                    write_data[write_selected_bank] <= modified_entry;

                    valid_bits[write_selected_bank][lookup_addr] <= 1'b1;
                    
                    // Speical case for replacement op
                    if (op_reg == OP_REPLACE && replace_phase_reg) begin
                        // free the old addr
                        valid_bits[replace_old_bank_reg][replace_old_addr_reg] <= 1'b0;

                        // second order_level update: add the new order 
                        order_level_symbol_reg <= replace_old_entry_reg.symbol;
                        order_level_side_reg <= replace_old_entry_reg.side;
                        order_level_price_reg <= price_reg;
                        order_level_quantity_reg <= $signed({1'b0, quantity_reg});
                        order_level_order_count_reg <= 2'sd1;

                        replace_phase_reg <= 1'b0;


                    end

                    state <= ST_ORDER_LEVEL;
                end

                ST_ORDER_LEVEL: begin
                    if(order_level_ready) begin
                        // during the first replace level update, the old-level removal just got accepted
                        // so we need to back to ST_WRITE to insert the replacement order to the order_level
                        if (op_reg == OP_REPLACE && replace_phase_reg) begin
                            state <= ST_WRITE;
                        end

                        else begin
                            state <= ST_DONE;
                        end
                    end

                end
                //Personally think DONE state is unneccesary here
                //leaving this for future improvement 
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

