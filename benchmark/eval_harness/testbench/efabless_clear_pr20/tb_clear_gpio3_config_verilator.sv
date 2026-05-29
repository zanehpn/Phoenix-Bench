module tb_clear_gpio3_config;
    logic mgmt_boot_i;
    logic gpio3_pullup_o;
    logic gpio3_pulldown_o;
    logic [12:0] gpio3_mode_o;

    gpio_power_on_config dut (
        .mgmt_boot_i,
        .gpio3_pullup_o,
        .gpio3_pulldown_o,
        .gpio3_mode_o
    );

    initial begin
        mgmt_boot_i = 1'b0;
        #1;
        if (gpio3_pullup_o || gpio3_pulldown_o) begin
            $fatal(1, "GPIO 3 pull state should be inactive before management boot");
        end

        mgmt_boot_i = 1'b1;
        #1;
        if (!gpio3_pullup_o) begin
            $fatal(1, "GPIO 3 did not power up with management pullup, mode=%h", gpio3_mode_o);
        end
        if (gpio3_pulldown_o) begin
            $fatal(1, "GPIO 3 still reports the old management pulldown mode");
        end
        $finish;
    end
endmodule
