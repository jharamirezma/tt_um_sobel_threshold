`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif

module spi_control (
        input logic     clk_i,
        input logic     nreset_i,

        //SPI interface
        input logic     spi_sck_i,
        input logic     spi_sdi_i,
        input logic     spi_cs_i,
        output logic    spi_sdo_o,

        //Sobel Interface
        output logic    [MAX_PIXEL_BITS-1:0] input_px_gray_o,
        input logic     [MAX_PIXEL_BITS-1:0] output_px_sobel_i,
        input logic     px_rdy_o_spi_i,
        output logic    px_rdy_i_spi_o
    );
    

    logic [MAX_PIXEL_BITS-1:0] data_rx;
    logic [MAX_PIXEL_BITS-1:0] data_tx; 
    logic [MAX_PIXEL_BITS-1:0] spi_data_rx;

    logic spi_rxtx_done;
    logic rxtx_done;
    logic rxtx_done_reg;

    spi_dep_signal_synchronizer signal_sync1 (
        .clk_i(clk_i),
        .nreset_i(nreset_i),
        .async_signal_i(spi_rxtx_done),
        .signal_o(rxtx_done)
    );

    logic rxtx_done_rising;
    assign rxtx_done_rising = rxtx_done & ~rxtx_done_reg;

    always_ff @(posedge clk_i or negedge nreset_i) begin
        if(!nreset_i) begin
            rxtx_done_reg <= 1'b0;
            data_rx <= 24'd0;
            px_rdy_i_spi_o <= 1'b0;
        end else begin
            rxtx_done_reg <= rxtx_done;
            if(rxtx_done_rising)begin
                data_rx <= spi_data_rx;
                px_rdy_i_spi_o <= 1'b1;
            end else begin
                data_rx <= data_rx;
                px_rdy_i_spi_o <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge nreset_i) begin
        if(!nreset_i) begin
            data_tx <= 24'd0;
        end else begin
            if(px_rdy_o_spi_i)begin
                data_tx <= output_px_sobel_i;
            end
        end
    end
 
    // SPI Slave Core
    spi_core #(
        .WORD_SIZE(MAX_PIXEL_BITS)
    ) spi0 (
        .sck_i(spi_sck_i),
        .sdi_i(spi_sdi_i),
        .cs_i(spi_cs_i),
        .sdo_o(spi_sdo_o),
        .data_tx_i({data_tx[7:0], data_tx[15:8], data_tx[23:16]}),
        .data_rx_o({spi_data_rx[7:0], spi_data_rx[15:8], spi_data_rx[23:16]}),
        .rxtx_done_o(spi_rxtx_done)
    );

    assign input_px_gray_o = data_rx;

endmodule