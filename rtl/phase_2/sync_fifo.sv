// synchorous FIFO placed between parser and upstream input
// both the write side and read side use the same clock
// writes only then FIFO is not full and the byte is valid
// reads only when it's not empty and parser is ready


module sync_fifo 

(
    input logic clk,
    input logic rst,

    // upstream input interface
    input logic[7:0] data_in,
    input logic byte_valid,
    output logic fifo_ready,
    
    // parser input interface
    input logic parser_ready,
    output logic[7:0] fifo_out,
    output logic fifo_byte_valid

);

    logic full, empty;
    logic[4:0] count;
    logic[3:0] write_pointer, read_pointer;
    logic write_en, read_en;

    logic [7:0] memory[0:15];


    assign empty = (count == 0);
    assign full = (count == 16);
    assign fifo_ready = !full;
    assign fifo_byte_valid = !empty;
    assign write_en = byte_valid && fifo_ready;
    assign read_en = parser_ready && fifo_byte_valid;

    assign fifo_out = memory[read_pointer];

    always_ff @(posedge clk) begin
        if (rst) begin

            write_pointer <= '0;
            read_pointer <= '0;
            count <= '0;
        end

        else begin
            if(write_en) begin
                memory[write_pointer] <= data_in;
                if (write_pointer == 15) begin
                    write_pointer <= '0;
                end
                
                else begin
                    write_pointer <= write_pointer + 1'd1;
                end

            end
            
            if (read_en) begin
                if (read_pointer == 15) begin
                    read_pointer <= '0;
                end
                
                else begin
                    read_pointer <= read_pointer + 1'd1;
                end 
            end

            case ({write_en, read_en}) 
                2'b10: begin
                    count <= count + 1'd1;
                end
                2'b01: begin
                    count <= count - 1'd1;
                end
                2'b11: begin
                    count <= count;
                end
                2'b00: begin
                    count <= count;
                end
            endcase

        end
    end





endmodule


