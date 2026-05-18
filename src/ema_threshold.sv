// ================================================================
//  ema_threshold.sv
//
//  Adaptive threshold based on EMA (Exponential Moving Average)
//  Designed to connect directly after sobel_control output.
//
//  Interface matches sobel_control:
//    - clk_i    / nreset_i  (same clock domain)
//    - px_rdy_i             (connected to px_rdy_o from sobel_control)
//    - in_px_i              (connected to out_px_sobel_o from sobel_control)
//    - start_threshold_i    (enable signal — active high)
//    - px_rdy_o             (output valid pulse)
//    - out_px_o             (binarized pixel: 0 or MAX_VAL)
//
//  Algorithm (per valid pixel, when start_threshold_i = 1):
//
//    -- Fixed-point format Q(PIXEL_WIDTH_OUT).(K) --
//    pixel_fp  = pixel_in << K
//    diff      = pixel_fp - mu_fp              (signed)
//    mu_fp    += diff >>> K                    (arithmetic shift)
//    abs_diff  = |diff|
//    err_sigma = abs_diff - sigma_fp
//    sigma_fp += err_sigma >>> K               (arithmetic shift)
//    mu_int    = mu_fp >> K                    (integer part)
//    sigma_int = sigma_fp >> K
//    T         = mu_int + 2*sigma_int          (saturated to MAX_VAL)
//    out       = (pixel_in >= T) ? MAX : 0
//
//  Features:
//    - No large accumulators -- only (PIXEL_WIDTH_OUT + K) bit registers
//    - Resolution-independent (no dependency on image size)
//    - Latency: 1 clock cycle
//    - K defined in parameters.svh (must be power of 2)
//
//  Reference:
//    Niblack, W. "An Introduction to Digital Image Processing"
//    Prentice-Hall, 1986, pp. 115-116.
//    T = mu + k*sigma applied globally over Sobel gradient magnitude.
// ================================================================

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

    // ── Fixed-point format Q(PIXEL_WIDTH_OUT).(K) ────────────
    // FP_W = PIXEL_WIDTH_OUT + K
    // Upper PIXEL_WIDTH_OUT bits = integer part
    // Lower K bits               = fractional part (precision across shifts)
    localparam int FP_W = PIXEL_WIDTH_OUT + K;

    logic signed [FP_W-1:0] mu_fp;        // mean  in fixed-point
    logic signed [FP_W-1:0] sigma_fp;     // sigma in fixed-point

    // ── Internal signals ─────────────────────────────────────
    logic signed [FP_W:0]          diff;        // pixel_fp - mu_fp (1 extra sign bit)
    logic        [FP_W-1:0]        abs_diff;    // |diff|
    logic signed [FP_W:0]          err_sigma;   // abs_diff - sigma_fp
    logic        [PIXEL_WIDTH_OUT-1:0] mu_int;    // integer part of mu
    logic        [PIXEL_WIDTH_OUT-1:0] sigma_int; // integer part of sigma
    logic        [PIXEL_WIDTH_OUT+1:0]   T_sum;     // mu_int + 2*sigma_int (overflow bit)
    logic        [PIXEL_WIDTH_OUT-1:0] T;         // threshold saturated to MAX_VAL

    // ── Fixed-point conversion of input pixel ────────────────
    // Scale pixel_in to fixed-point by shifting K bits left
    logic signed [FP_W:0] pixel_fp;
    assign pixel_fp = $signed({{(FP_W-PIXEL_WIDTH_OUT){1'b0}}, in_px_i}) <<< K;

    // ── Combinational computation ────────────────────────────

    // diff = pixel_fp - mu_fp  (signed fixed-point)
    assign diff = pixel_fp - $signed({1'b0, mu_fp});

    // abs_diff = |diff|
    assign abs_diff = diff[FP_W] ? FP_W'(-diff) : FP_W'(diff);

    // err_sigma = abs_diff - sigma_fp
    assign err_sigma = $signed({1'b0, abs_diff}) - $signed({1'b0, sigma_fp});

    // Extract integer parts (upper PIXEL_WIDTH_OUT bits)
    assign mu_int    = mu_fp[FP_W-1:K];
    assign sigma_int = sigma_fp[FP_W-1:K];

    // T = mu_int + 2*sigma_int  (shift left 1 = x2, no multiplier)
    // Extra overflow bit detects saturation
    assign T_sum = {2'b00, mu_int} + {1'b0, sigma_int, 1'b0};
    assign T     = T_sum[PIXEL_WIDTH_OUT+1] || T_sum[PIXEL_WIDTH_OUT] ? MAX_VAL : T_sum[PIXEL_WIDTH_OUT-1:0];
    
    // ── EMA register update ──────────────────────────────────
    always_ff @(posedge clk_i or negedge nreset_i) begin
        if (!nreset_i) begin
            // Initial estimates for the first frame
            // 30 and 20 are reasonable starting points for Sobel magnitude
            mu_fp    <= FP_W'(30) <<< K;
            sigma_fp <= FP_W'(20) <<< K;
        end else if (px_rdy_i && start_threshold_i) begin
            // mu    += diff >>> K     (arithmetic right shift preserves sign)
            // sigma += err_sigma >>> K
            mu_fp    <= mu_fp    + (diff     >>> K);
            sigma_fp <= sigma_fp + (err_sigma >>> K);
        end
        // No reset on end-of-frame:
        // EMA state carries over as warm start for the next frame
    end

    // ── Output register (1 cycle latency) ────────────────────
    // pixel_in is compared against T computed from the previous cycle
    // T is stable while mu/sigma update in parallel
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
                // Threshold disabled -- hold outputs low
                out_px_o <= ZERO;
                px_rdy_o <= 1'b0;
            end
        end
    end

endmodule