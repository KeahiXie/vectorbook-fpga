/*
This file has four helpful task: send_byte, send_add, send_replace and check_bid,
*/


// Sends one byte using valid/ready
task automatic send_byte(input logic [7:0] value);
    // handshake logic: a transfer happens only on a rising clock edge
    // when both byte_valid and byte_read are high
    @(negedge clk);
    data_in = value;
    byte_valid = 1'b1;

    //wait until the parser accepts it
    do begin
        @(posedge clk);
    end while(!byte_read);

    //stop offeing the byte 
    @(negedge clk);
    byte_valid = 1'b0;

endtask


// Constructs an Add message and sends its bytes
task automatic send_add(
    input logic [63:0] order_id,
    input logic [15:0] stock_locate,
    input logic        side,
    input logic [31:0] quantity,
    input logic [31:0] price
);
    // byte0: message type
    send_byte("A");

    // bytes 1-2: stock locate, highest byte first
    send_byte(stock_locate[15:8]);
    send_byte(stock_locate[7:0]);

    // bytes 3-10: tracking number and timestamp
    repeat (8) begin
        send_byte(8'h00);
    end

    // bytes 11-18: order ID
    for (int i = 7; i >= 0; i--) begin
        send_byte(order_id[i*8 +: 8]);
    end

    // byte 19: side, 0 = buy and 1 = sell
    if (side)
        send_byte("S");
    else
        send_byte("B");

    // bytes 20-23: quantity
    for (int i = 3; i >= 0; i--) begin
        send_byte(quantity[i*8 +: 8]);
        // singal[start +: width]
        // quantity[31:24]
    end

    // bytes 24-31: stock name
    // our parser uses stock locate, so use spaces here
    repeat (8) begin
        send_byte(8'h20);
    end

    // bytes 32-35: price
    for (int i=3; i >= 0; i--) begin
        send_byte(price[i*8 +: 8]);
    end


endtask


// Constructs a Replace message and sends its bytes
task automatic send_replace(
    input logic [63:0] old_order_id,
    input logic [63:0] new_order_id,
    input logic [15:0] stock_locate,
    input logic [31:0] quantity,
    input logic [31:0] price
);
    // byte 0: replace message
    send_byte("U");

    // bytes 1-2: stock locate
    send_byte(stock_locate[15:8]);
    send_byte(stock_locate[7:0]);

    // bytes 3-10: tracking number and timestamp
    repeat (8) begin
        send_byte(8'h00);
    end

    // bytes 11-18: old order ID
    for (int i = 7; i >= 0; i--) begin
        send_byte(old_order_id[i*8 +: 8]);
    end

    // bytes 19-26: new order ID
    for (int i = 7; i >= 0; i--) begin
        send_byte(new_order_id[i*8 +: 8]);
    end

    // bytes 27-30: new quantity
    for (int i = 3; i >= 0; i--) begin
        send_byte(quantity[i*8 +: 8]);
    end

    // bytes 31-34: new price
    for (int i = 3; i >= 0; i--) begin
        send_byte(price[i*8 +: 8]);
    end

endtask

    task automatic check_bid(
        input logic [31:0] expected_price,
        input logic [31:0] expected_quantity,
        input logic [15:0] expected_count
    );

        wait (operation_done == 1'b1);
        @(negedge clk);
        
        print_tables();

        if (best_bid_valid[0] !== 1'b1 ||
            best_bid_price[0] !== expected_price ||
            best_bid_quantity[0] !== expected_quantity ||
            best_bid_order_count[0] !== expected_count) begin

            $display("Expected: price=%0d quantity=%0d count=%0d",
                expected_price,
                expected_quantity,
                expected_count);

            $fatal(1,
                "Actual: valid=%b price=%0d quantity=%0d count=%0d",
                best_bid_valid[0],
                best_bid_price[0],
                best_bid_quantity[0],
                best_bid_order_count[0]);
        end

        $display("PASS: best bid price=%0d quantity=%0d count=%0d",
            best_bid_price[0],
            best_bid_quantity[0],
            best_bid_order_count[0]);

        // wait for this operation's done signal to clear
        wait (operation_done == 1'b0);

    endtask