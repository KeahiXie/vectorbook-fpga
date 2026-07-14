`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/13/2026 06:43:52 PM
// Design Name: 
// Module Name: tiny_queto_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tiny_queto_rx(
    input logic clk,
    input logic rst,
    input logic byte_valid,
    input logic[7:0] data_in,
    
    output logic[7:0] symbol,
    output logic[15:0] price,
    output logic queto_valid 
    // in this project we need a queto_valid output bc we want to  
    // receive all three patches before actaully start using the data
    );

logic[1:0] byte_index;
logic[7:0] price_high;


always_ff @(posedge clk) begin
    if(rst) begin
            byte_index <= 2'd0;
            symbol <= 8'd0;
            price <= 16'd0;
            queto_valid <= 1'd0;
            price_high <= 8'd0;
            end 
    
    else begin
        queto_valid <= 1'b0;
        if(byte_valid) begin
                       case(byte_index)
                            2'd0: begin
                                  symbol <= data_in;
                                  byte_index <= 2'd1;
                            end
                            2'd1: begin
                                  price_high <=data_in;
                                  byte_index <= 2'd2;                            
                            end   
                            
                            2'd2: begin
                                  price <= {price_high, data_in};
                                  queto_valid <= 1'b1;
                                  byte_index <= 2'd0;
                                  
                            end     
                            
                       endcase
                       end
        
        
    
    
    end
        
    

end

endmodule
