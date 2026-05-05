`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif


module top_gray_sobel(
        input logic    clk_i,
        input logic    nreset_i,

        input logic    [1:0] select_i,
        input logic    start_sobel_i,
        input logic    px_rdy_i,
        input logic    [MAX_PIXEL_BITS-1:0] in_pixel_i,

        output logic   [MAX_PIXEL_BITS-1:0] out_pixel_o,
        output logic   px_rdy_o
    );

    logic px_rdy_i_sobel;

    logic select_sobel_mux;
    logic [PIXEL_WIDTH_OUT-1:0] in_px_sobel;

    logic [PIXEL_WIDTH_OUT-1:0] out_px_gray;
    logic [PIXEL_WIDTH_OUT-1:0] out_px_sobel;

    logic px_rdy_o_gray;
    logic px_rdy_o_sobel;

    //Gray scale instance
    gray_scale_core gray_scale0 (
        .clk_i(clk_i),
        .nreset_i(nreset_i),
        .px_rdy_i(px_rdy_i),
        .in_px_rgb_i(in_pixel_i),
        .out_px_gray_o(out_px_gray),
        .px_rdy_o(px_rdy_o_gray)
    );

    //Sobel instance
    sobel_control sobel0 (
        .clk_i(clk_i),
        .nreset_i(nreset_i),
        .start_sobel_i(start_sobel_i),
        .px_rdy_i(px_rdy_i_sobel),
        .in_px_sobel_i(in_px_sobel),
        .out_px_sobel_o(out_px_sobel),
        .px_rdy_o(px_rdy_o_sobel)
    );

    assign select_sobel_mux = select_i[0];
    assign in_px_sobel = select_sobel_mux ?  in_pixel_i[7:0] : out_px_gray;

    always_comb begin
        case(select_i)
            2'b00: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};    //Complete pipeline
                px_rdy_i_sobel = px_rdy_o_gray;
                px_rdy_o = px_rdy_o_sobel;
            end
            2'b01: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};    //Only sobel
                px_rdy_i_sobel = px_rdy_i;
                px_rdy_o = px_rdy_o_sobel;
            end
            2'b10: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_gray};     //Only grayscale
                px_rdy_i_sobel = 1'b0;   
                px_rdy_o = px_rdy_o_gray;
            end
            2'b11: begin
                out_pixel_o = in_pixel_i;                                 //Bypass
                px_rdy_i_sobel = 1'b0;                          
                px_rdy_o = px_rdy_i;
            end
            default: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};    //Only sobel
                px_rdy_i_sobel = px_rdy_i;
                px_rdy_o = px_rdy_o_sobel;
            end
        endcase
    end
    
endmodule
