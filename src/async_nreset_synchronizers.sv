module spi_dep_async_nreset_synchronizer (
        input  logic clk_i,
        input  logic async_nreset_i,
        input  logic tied_value_i,
        output logic nreset_o
    );
    
    logic r_sync;

    always_ff @(posedge clk_i or negedge async_nreset_i) begin
        if (!async_nreset_i) begin
            {nreset_o, r_sync} <= 2'b00;
        end else begin
            {nreset_o, r_sync} <= {r_sync, tied_value_i};
        end
    end

endmodule

module spi_dep_signal_synchronizer (
        input  logic clk_i,
        input  logic nreset_i,
        input  logic async_signal_i,
        output logic signal_o
    );

    logic signal_sync;

    always_ff @(posedge clk_i or negedge nreset_i) begin
        if (!nreset_i) begin
            {signal_o, signal_sync} <= '0;
        end else begin
            {signal_o, signal_sync} <= {signal_sync,async_signal_i};
        end
    end


endmodule
