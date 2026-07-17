module quote_rx_5byte_ready(
    input logic clk,
    input logic rst,
    input logic byte_valid,
    
    input logic[7:0] data_in,
    
    
    output logic[7:0] symbol,
    output logic[31:0] price,
    output logic ready,
    output logic quote_valid 
    // in this project we need a quote_valid output bc we want to  
    // receive all three patches before actaully start using the data
    );

logic[2:0] byte_index;
logic[7:0] price_b3, price_b2, price_b1;
logic cooldown;

assign ready = !cooldown;




always_ff @(posedge clk) begin
    if(rst) begin
            byte_index <= 3'd0;
            symbol <= 8'd0;
            price <= 32'd0;
            quote_valid <= 1'd0;
            price_b3 <= 8'd0;
            price_b2 <= 8'd0;
            price_b1 <= 8'd0;
            cooldown <= 1'b0;
            end 
    
    else begin
        quote_valid <= 1'b0;

        if (cooldown)  begin
            cooldown <= 1'b0;
        end

        if(byte_valid && ready) begin
                       case(byte_index)
                            3'd0: begin
                                  symbol <= data_in;
                                  byte_index <= 3'd1;
                            end
                            3'd1: begin
                                  price_b3 <=data_in;
                                  byte_index <= 3'd2;                            
                            end   
                            
                            3'd2: begin
                                  price_b2 <= data_in;
                                  byte_index <= 3'd3;
                              end
                             3'd3: begin
                                  price_b1 <= data_in;
                                  byte_index <= 3'd4;
                              end
                            3'd4: begin
                                  price <= {price_b3, price_b2, price_b1, data_in};
                                  byte_index <= 3'd0;
                                  quote_valid <= 1'b1;
                                  cooldown <= 1'b1;
                              end   
                            
                       endcase
                       end
                  end
                end
        
 endmodule       
    