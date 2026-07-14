`timescale 1ns/1ps

module quote_rx_5byte_ready_tb;

logic clk;
logic byte_valid;
logic rst;
logic[7:0] symbol;
logic[7:0] data_in;
logic[31:0] price;
logic ready;
logic quote_valid;

quote_rx_5byte_ready dut(
    .clk(clk),
    .byte_valid(byte_valid),
    .rst(rst),
    .symbol(symbol),
    .data_in(data_in),
    .price(price),
    .quote_valid(quote_valid),  
    .ready(ready)
);


//create the clock
always #5 clk = ~clk;

initial begin
    
    clk = 0;
    rst = 1;
    byte_valid = 1;
    data_in = 0;



    repeat (2) @(posedge clk);


    // wait for an event
    // the line below means wait for the next rising edge
    // to set rest to 0
    @(posedge clk);
    rst = 0;

    byte_valid = 1;
    data_in = 8'h02;

    @(negedge clk);
    data_in = 8'h00;

    @(negedge clk);
    data_in = 8'h0F;

    @(negedge clk);
    data_in = 8'h42;

    @(negedge clk);
    data_in = 8'h40;


    // wait for 2ns 
    #2;


    $display("symbol = %0d", symbol);
    $display("price = %0d", price);
    $display("quote_valid = %0d", quote_valid);


    @(posedge clk);

    #20;
    byte_valid = 0;
    $finish;
end

endmodule