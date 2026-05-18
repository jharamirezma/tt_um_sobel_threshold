`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif

module ema_threshold (
    input  logic                        clk_i,
    input  logic                        nreset_i,

    // Input stream -- connect to sobel_control outputs
    input  logic [PIXEL_WIDTH_OUT-1:0]  in_px_i,           // out_px_sobel_o
    input  logic                        px_rdy_i,           // px_rdy_o from sobel_control
    input  logic                        start_threshold_i,  // enable -- active high

    // Binarized output
    output logic [PIXEL_WIDTH_OUT-1:0]  out_px_o,
    output logic                        px_rdy_o
);

    // ── Saturation constants ─────────────────────────────────
    localparam logic [PIXEL_WIDTH_OUT-1:0] MAX_VAL = {PIXEL_WIDTH_OUT{1'b1}};  // 255
    localparam logic [PIXEL_WIDTH_OUT-1:0] ZERO    = {PIXEL_WIDTH_OUT{1'b0}};  // 0

    // ── Fixed-point format Q(PIXEL_WIDTH_OUT).(K_SLOW) ───────
    // K_SLOW is the base precision
    // K_FAST must be < K_SLOW (both defined in parameters.svh)
    localparam int FP_W = PIXEL_WIDTH_OUT + K_SLOW;

    logic signed [FP_W-1:0] mu_fp;        // mean  in fixed-point
    logic signed [FP_W-1:0] sigma_fp;     // sigma in fixed-point

    // ── Internal signals ─────────────────────────────────────
    logic signed [FP_W:0]          diff;        // pixel_fp - mu_fp (1 extra sign bit)
    logic        [FP_W-1:0]        abs_diff;    // |diff|
    logic signed [FP_W:0]          err_sigma;   // abs_diff - sigma_fp
    logic        [PIXEL_WIDTH_OUT-1:0] mu_int;    // integer part of mu
    logic        [PIXEL_WIDTH_OUT-1:0] sigma_int; // integer part of sigma
    logic        [PIXEL_WIDTH_OUT+1:0] T_sum;     // mu_int + 2*sigma_int (overflow bits)
    logic        [PIXEL_WIDTH_OUT-1:0] T;         // threshold saturated to MAX_VAL

    // ── Dual-speed: detect abrupt scene change ────────────────
    // big_change = |pixel - mu| > 4*sigma
    // abs_diff integer part vs sigma_int << 2  (x4, no multiplier)
    logic [PIXEL_WIDTH_OUT-1:0] abs_diff_int;
    logic                       big_change;

    // ── Fixed-point conversion of input pixel ────────────────
    logic signed [FP_W:0] pixel_fp;
    assign pixel_fp = $signed({{(FP_W-PIXEL_WIDTH_OUT+1){1'b0}}, in_px_i}) <<< K_SLOW;
    
    // ── Combinational computation ────────────────────────────

    // diff = pixel_fp - mu_fp  (signed fixed-point)
    assign diff = pixel_fp - $signed({1'b0, mu_fp});

    // abs_diff = |diff|
    assign abs_diff = diff[FP_W] ? FP_W'(-diff) : FP_W'(diff);

    // err_sigma = abs_diff - sigma_fp
    assign err_sigma = $signed({1'b0, abs_diff}) - $signed({1'b0, sigma_fp});

    // Extract integer parts (upper PIXEL_WIDTH_OUT bits)
    assign mu_int       = mu_fp[FP_W-1:K_SLOW];
    assign sigma_int    = sigma_fp[FP_W-1:K_SLOW];
    assign abs_diff_int = abs_diff[FP_W-1:K_SLOW];

    // big_change if |pixel - mu| > 4*sigma  (shift 2 = x4, no multiplier)
    assign big_change = (abs_diff_int > {sigma_int[PIXEL_WIDTH_OUT-3:0], 2'b00});

    // T = mu_int + 2*sigma_int, saturated to MAX_VAL
    assign T_sum = {2'b00, mu_int} + {1'b0, sigma_int, 1'b0};
    assign T     = T_sum[PIXEL_WIDTH_OUT+1] || T_sum[PIXEL_WIDTH_OUT] ? MAX_VAL : T_sum[PIXEL_WIDTH_OUT-1:0];

    // ── EMA dual-speed register update ───────────────────────
    always_ff @(posedge clk_i or negedge nreset_i) begin
        if (!nreset_i) begin
            mu_fp    <= FP_W'(30) <<< K_SLOW;
            sigma_fp <= FP_W'(20) <<< K_SLOW;
        end else if (px_rdy_i && start_threshold_i) begin
            if (big_change) begin
                mu_fp    <= FP_W'(mu_fp    + (diff     >>> K_FAST));
                sigma_fp <= FP_W'(sigma_fp + (err_sigma >>> K_FAST));
            end else begin
                mu_fp    <= FP_W'(mu_fp    + (diff     >>> K_SLOW));
                sigma_fp <= FP_W'(sigma_fp + (err_sigma >>> K_SLOW));
            end
        end
    end

    // ── Output register (1 cycle latency) ────────────────────
    always_ff @(posedge clk_i or negedge nreset_i) begin
        if (!nreset_i) begin
            out_px_o <= ZERO;
            px_rdy_o <= 1'b0;
        end else begin
            if (start_threshold_i) begin
                px_rdy_o <= px_rdy_i;
                if (px_rdy_i)
                    out_px_o <= (in_px_i >= T) ? MAX_VAL : ZERO;
                else
                    out_px_o <= ZERO;
            end else begin
                out_px_o <= ZERO;
                px_rdy_o <= 1'b0;
            end
        end
    end

endmodule