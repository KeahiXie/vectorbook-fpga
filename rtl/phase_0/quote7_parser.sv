// The lines was commented with one line was sugguested by AI for my code

module quote7_parser (
    input logic clk,
    input logic rst,
    input logic byte_valid,

    input logic[7:0] data_in,

    output logic ready,
    output logic[7:0] event_symbol,
    output logic event_valid,
    output logic[15:0] event_bid_price, 
    output logic[15:0] event_ask_price,
    output logic[7:0]  event_bid_quantity,
    output logic[7:0]  event_ask_quantity
 
);

logic[2:0] byte_index;
logic[7:0] temp_bid_price_b1, temp_bid_price_b0, temp_ask_price_b1, temp_ask_price_b0;
logic[7:0] temp_bid_quantity, temp_ask_quantity;
logic[7:0] temp_symbol;




always_ff@(posedge clk) begin
    event_valid <= 1'b0;
    ready <= 1'b1;
    if(rst) begin
        byte_index <= 3'd0;
        temp_symbol <= 8'd0;
        temp_bid_price_b1 <= 8'd0;
        temp_bid_price_b0 <= 8'd0;
        temp_bid_quantity <= 8'd0;
        temp_ask_price_b1 <= 8'd0;
        temp_ask_price_b0 <= 8'd0;
        temp_ask_quantity <= 8'd0;
        event_valid <= 1'b0;
        event_symbol <= 8'd0;
        event_bid_price <= 16'd0;
        event_bid_quantity <= 8'd0;
        event_ask_price <= 16'd0;
        event_ask_quantity <= 8'd0;
        ready <= 1'b1;
    end
    else begin
        if (byte_index == 3'd7) begin
            event_symbol       <= temp_symbol;
            event_bid_price    <= {temp_bid_price_b1, temp_bid_price_b0};
            event_bid_quantity <= temp_bid_quantity;
            event_ask_price    <= {temp_ask_price_b1, temp_ask_price_b0};
            event_ask_quantity <= temp_ask_quantity;
            event_valid <= 1'b1;
            byte_index  <= 3'd0;         
        end    
        else if (byte_valid && ready) begin
        case(byte_index)
        3'd0:begin
            byte_index <= 3'd1;
            temp_symbol <= data_in;
        end
        3'd1:begin
            byte_index <= 3'd2;
            temp_bid_price_b1 <= data_in;
        end
        3'd2: begin
            byte_index <= 3'd3;
            temp_bid_price_b0 <= data_in;
        end
        3'd3: begin
            byte_index <= 3'd4;
            temp_bid_quantity <= data_in;
        end

        3'd4: begin
            byte_index <= 3'd5;
            temp_ask_price_b1 <= data_in;
        end

        3'd5: begin
            byte_index <= 3'd6;
            temp_ask_price_b0 <= data_in;
        end

        3'd6: begin
            byte_index <=3'd7;
            temp_ask_quantity <= data_in;
            ready <= 1'b0; // we will be uploading event data from the register so no more data in 
            
        end


        default: begin
            byte_index <= 3'd0;
        end

        endcase
    end

end
end
endmodule