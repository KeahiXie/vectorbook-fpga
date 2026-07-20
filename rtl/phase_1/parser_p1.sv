


module parser_p1 # (
    parameter int PRICE_WIDTH = 32,
    parameter int QUANTITY_WIDTH = 16,
    parameter int TOTAL_BYTES = ((PRICE_WIDTH * 2) + (QUANTITY_WIDTH * 2) + 8) / 8,
    parameter int BYTE_INDEX_WIDTH = $clog2(TOTAL_BYTES+1)

)
(
    input logic clk,
    input logic rst,
    input logic byte_valid,

    input logic[7:0] data_in,

    output logic ready,
    output logic[7:0] event_symbol,
    output logic event_valid,
    output logic[PRICE_WIDTH-1:0] event_bid_price, 
    output logic[PRICE_WIDTH-1:0] event_ask_price,
    output logic[QUANTITY_WIDTH-1:0]  event_bid_quantity,
    output logic[QUANTITY_WIDTH-1:0]  event_ask_quantity
 
);



logic[BYTE_INDEX_WIDTH-1:0] byte_index;
logic[PRICE_WIDTH-1:0] temp_bid_price, temp_ask_price;
logic[QUANTITY_WIDTH-1:0] temp_bid_quantity, temp_ask_quantity;
logic[7:0] temp_symbol;


always_ff @(posedge clk) begin

    if (rst) begin
        byte_index <= '0;
        temp_symbol <= 8'd0;
        temp_bid_price <= '0;
        temp_bid_quantity <= '0;
        temp_ask_price <= '0;
        temp_ask_quantity <= '0;
        event_valid <= 1'b0;
        event_symbol <= 8'd0;
        event_bid_price <= '0;
        event_bid_quantity <= '0;
        event_ask_price <= '0;
        event_ask_quantity <= '0;
        ready <= 1'b1;
    end

    else begin
        ready <= 1'b1;
        event_valid <= 1'b0;
        // update pulse doesn't care if parser is ready or not 
        if (byte_valid && ready) begin
            case(byte_index)
                'd0:begin
                    temp_symbol <= data_in;
                    byte_index <= 'd1;
                end
                'd1:begin
                    temp_bid_price <= {temp_bid_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd2;
                end
                'd2:begin
                    temp_bid_price <= {temp_bid_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd3;
                end
                'd3:begin
                    temp_bid_price <= {temp_bid_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd4;
                end
                'd4:begin
                    temp_bid_price <= {temp_bid_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd5;
                end
                'd5:begin
                    temp_bid_quantity <= {temp_bid_quantity[QUANTITY_WIDTH-9:0], data_in};
                    byte_index <= 'd6;
                end
                'd6:begin
                    temp_bid_quantity <= {temp_bid_quantity[QUANTITY_WIDTH-9:0], data_in};
                    byte_index <= 'd7;
                end
                'd7:begin
                    temp_ask_price <= {temp_ask_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd8;
                end
                'd8:begin
                    temp_ask_price <= {temp_ask_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd9;
                end
                'd9:begin
                    temp_ask_price <= {temp_ask_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd10;
                end
                'd10:begin
                    temp_ask_price <= {temp_ask_price[PRICE_WIDTH-9:0], data_in};
                    byte_index <= 'd11;
                end
                'd11:begin
                    temp_ask_quantity <= {temp_ask_quantity[QUANTITY_WIDTH-9:0], data_in};
                    byte_index <= 'd12;
                end
                'd12:begin
                    temp_ask_quantity <= {temp_ask_quantity[QUANTITY_WIDTH-9:0], data_in};
                    byte_index <= 'd13;
                    ready <= 1'b0;
                end    
            endcase
        end
        // parser can publish quote anytime when it reaches 13 doesn't matter whether it's ready or not
        if (byte_index == 'd13) begin
            event_symbol       <= temp_symbol;
            event_bid_price    <= temp_bid_price;
            event_bid_quantity <= temp_bid_quantity;
            event_ask_price    <= temp_ask_price;
            event_ask_quantity <= temp_ask_quantity;
            event_valid <= 1'b1;
            byte_index  <= 'd0;
            ready <= 'b1;
        end

    end



end 
endmodule

