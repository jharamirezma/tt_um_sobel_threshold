`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif

module gray_scale_core(
        input logic    clk_i,
        input logic    nreset_i,

        input logic    px_rdy_i,
        input logic    [MAX_PIXEL_BITS-1:0] in_px_rgb_i,

        output logic   [PIXEL_WIDTH_OUT-1:0] out_px_gray_o,
        output logic   px_rdy_o

    );

    logic [PIXEL_WIDTH_OUT-1:0] red;
    logic [PIXEL_WIDTH_OUT-1:0] green;
    logic [PIXEL_WIDTH_OUT-1:0] blue;

    always_ff @(posedge clk_i or negedge nreset_i)begin
        if (!nreset_i)begin
            out_px_gray_o <= 8'd0;
            px_rdy_o <= 1'b0;
        end else begin
            px_rdy_o <= px_rdy_i;
            out_px_gray_o <= (red>>2)+(red>>5)+(green>>1)+(green>>4)+(blue>>4)+(blue>>5);
        end
    end

    assign  red = in_px_rgb_i[MAX_PIXEL_BITS-1:16];
    assign  green = in_px_rgb_i[15:8];
    assign  blue = in_px_rgb_i[7:0];

endmodule
