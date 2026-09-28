// A task written by Chatgpt to print active orders and price levels

task automatic print_tables();

        logic [143:0] order_entry;
        logic [95:0] level_entry;

        $display("\nORDER STORE");
        $display("+------+-------+----------+--------+------+------------+------------+");
        $display("| Bank | Addr  | Order ID | Symbol | Side | Price      | Quantity   |");
        $display("+------+-------+----------+--------+------+------------+------------+");

        for (int bank = 0; bank < 3; bank++) begin
            for (int addr = 0; addr < 128; addr++) begin

                if (dut.u_order_store.valid_bits[bank][addr]) begin
                    order_entry = order_table[bank][addr];

                    $display(
                        "| %4d | %5d | %8d | %6d | %4s | %10d | %10d |",
                        bank,
                        addr,
                        order_entry[143:80],
                        order_entry[79:72],
                        order_entry[71] ? "Sell" : "Buy",
                        order_entry[70:39],
                        order_entry[38:7]
                    );
                end

            end
        end

        $display("+------+-------+----------+--------+------+------------+------------+");


        $display("\nORDER LEVEL");
        $display("+-------+--------+------+------------+----------------+-------------+");
        $display("| Addr  | Symbol | Side | Price      | Total Quantity | Order Count |");
        $display("+-------+--------+------+------------+----------------+-------------+");

        for (int addr = 0; addr < 128; addr++) begin

            if (dut.u_order_level.level_valid_bits_bram[addr]) begin
                level_entry = level_table[addr];

                $display(
                    "| %5d | %6d | %4s | %10d | %14d | %11d |",
                    addr,
                    level_entry[95:88],
                    level_entry[87] ? "Sell" : "Buy",
                    level_entry[86:55],
                    level_entry[54:23],
                    level_entry[22:7]
                );
            end

        end

        $display("+-------+--------+------+------------+----------------+-------------+");

    endtask