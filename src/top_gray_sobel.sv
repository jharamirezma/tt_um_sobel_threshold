`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif


module top_gray_sobel(
        input logic    clk_i,
        input logic    nreset_i,

        input logic    [2:0] select_i,
        input logic    start_sobel_i,
        input logic    start_threshold_i,
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
    logic [PIXEL_WIDTH_OUT-1:0] out_px_threshold;

    logic px_rdy_o_gray;
    logic px_rdy_o_sobel;
    logic px_rdy_o_threshold;

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

    ema_threshold  u_threshold (
        .clk_i    (clk_i),
        .nreset_i (nreset_i),
        .start_threshold_i (start_threshold_i), 
        .in_px_i  (out_px_sobel),   
        .px_rdy_i (px_rdy_o_sobel),   
        .out_px_o (out_px_threshold),    
        .px_rdy_o (px_rdy_o_threshold)     
    );

    assign select_sobel_mux = select_i[0];
    assign in_px_sobel = select_sobel_mux ?  in_pixel_i[7:0] : out_px_gray;

    always_comb begin
        case(select_i)
            3'b000: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_threshold};    //Input RGB -> gray -> sobel -> threshold
                px_rdy_i_sobel = px_rdy_o_gray;
                px_rdy_o = px_rdy_o_threshold;
            end
            3'b001: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_threshold};    //Input gray -> sobel -> threshold
                px_rdy_i_sobel = px_rdy_i;
                px_rdy_o = px_rdy_o_threshold;
            end
            3'b010: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};     //Input RGB -> gray -> sobel 
                px_rdy_i_sobel = px_rdy_o_gray;   
                px_rdy_o = px_rdy_o_sobel;
            end
            3'b011: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};     //Input gray -> sobel 
                px_rdy_i_sobel = px_rdy_i;                          
                px_rdy_o = px_rdy_o_sobel;
            end
            3'b100: begin
                out_pixel_o    = {{ZERO_PAD_WIDTH{1'b0}}, out_px_gray};  //Input RGB -> gray
                px_rdy_i_sobel = 1'b0;
                px_rdy_o       = px_rdy_o_gray;
            end
            3'b101: begin
                out_pixel_o    = in_pixel_i;                             // Input RGB -> Input RGB
                px_rdy_i_sobel = 1'b0;
                px_rdy_o       = px_rdy_i;
            end
            default: begin
                out_pixel_o = {{ZERO_PAD_WIDTH{1'b0}}, out_px_sobel};    //Only sobel
                px_rdy_i_sobel = px_rdy_i;
                px_rdy_o = px_rdy_o_sobel;
            end
        endcase
    end
    
endmodule
