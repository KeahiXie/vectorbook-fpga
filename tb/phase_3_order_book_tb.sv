`timescale 1ns/1ps

module phase_3_order_book_tb ();

    // clk generator 
    logic clk = 0;
    always # 4 clk = ~clk; 

endmodule;