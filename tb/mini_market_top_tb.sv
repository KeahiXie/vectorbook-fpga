// Description  :Testbench for minimarket_top
// Date         :2026-7-15

`timescale 1ns/1ps



module mini_market_top_tb();

    // creating a clock signal
    logic clk;
    logic rst;
    logic[7:0] data_in;
    logic byte_valid;
    logic ready;
    logic book_valid;
    logic book_update;
    logic[15:0] best_bid_price;
    logic[15:0] best_ask_price;
    logic[7:0] best_bid_quantity;
    logic[7:0] best_ask_quantity;

    mini_market_top dut(
        .clk(clk),
        .rst(rst),
        .byte_valid(byte_valid),
        .data_in(data_in),
        .ready(ready),
        .book_valid(book_valid),
        .book_update(book_update),
        .best_bid_price(best_bid_price),
        .best_ask_price(best_ask_price),
        .best_bid_quantity(best_bid_quantity),
        .best_ask_quantity(best_ask_quantity)
    );


    initial clk = 0;
    always #5 clk = ~clk;
    
    //creating a task so it's easier to send bytes
    task send_byte(input logic[7:0] b);
    byte_valid = 1'b1;
    data_in = b;
    @(posedge clk);
    while(!ready) @(posedge clk);
    byte_valid = 1'b0;
    endtask
    
    //
     task send_byte_nogap(input logic [7:0] b);
     data_in    = b;
     byte_valid = 1'b1;
     @(posedge clk);
     while (!ready) @(posedge clk);
     endtask    

    initial begin
        byte_valid = 1'b0;
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        
        send_byte_nogap(8'h02);
        send_byte_nogap(8'h03);
        send_byte_nogap(8'hE8);
        send_byte_nogap(8'h78);
        send_byte_nogap(8'h03);
        send_byte_nogap(8'hFC);
        send_byte_nogap(8'h28);
        send_byte_nogap(8'h02);
        send_byte_nogap(8'h03);
        send_byte_nogap(8'hED);
        send_byte_nogap(8'h64);
        send_byte_nogap(8'h03);
        send_byte_nogap(8'hF7);
        send_byte_nogap(8'h2D);
        byte_valid = 1'b0;

        
        
        send_byte(8'h02);   // symbol = 2
        send_byte(8'h03);   // bid price high byte
        send_byte(8'hE8);   // bid price low byte   -> 0x03E8 = 1000

        send_byte(8'h78);   // bid qty = 120
        send_byte(8'h03);   // ask price high byte
        send_byte(8'hFC);   // ask price low byte   -> 0x03FC = 1020
        send_byte(8'h28);   // ask qty = 40
        
        // symbol = 3 - wrong symbol book should not be updated
        send_byte(8'h03);
        send_byte(8'h02);
        send_byte(8'h03);
        send_byte(8'h04);
        send_byte(8'h05);
        send_byte(8'h06);
        send_byte(8'h07);
        
        send_byte(8'h02);   // symbol = 2
        send_byte(8'h03);   // bid price high byte
        send_byte(8'hED);   // bid price low byte   -> 0x03ED = 1005
        send_byte(8'h64);   // bid qty = 100
        send_byte(8'h03);   // ask price high byte
        send_byte(8'hF7);   // ask price low byte   -> 0x03F7 = 1015
        send_byte(8'h2D);   // ask qty = 45
            
        
        
        


        #200;
        $finish;
    end

endmodule