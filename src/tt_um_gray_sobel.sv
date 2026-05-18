// `ifdef COCOTB_SIM
//   `include "../src/parameters.svh"
// `else
//   `include "parameters.svh"
// `endif

`include "../src/parameters.svh"


module tt_um_gray_sobel (
      input  wire [7:0] ui_in,    // Dedicated inputs 
      output wire [7:0] uo_out,   // Dedicated outputs 
      input  wire [7:0] uio_in,   // IOs: Input path
      output wire [7:0] uio_out,  // IOs: Output path
      output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
      input  wire       ena,      // will go high when the design is enabled
      input  wire       clk,      // clock
      input  wire       rst_n     // reset_n - low to reset
  
  );

    
    logic nreset_async_i;

    assign nreset_async_i = rst_n;
    assign uio_oe  = 8'b10000000;        // bits [7] output, bits [6:0] input
    assign uio_out[7:0] = 8'b00000000;

    wire _unused = uio_in[7];

    //SPI interface
    logic spi_sck_i;
    logic spi_sdi_i;
    logic spi_cs_i;
    logic spi_sdo_o;
    assign spi_cs_i = ui_in[0];
    assign spi_sck_i = ui_in[1];
    assign spi_sdi_i = ui_in[2];

  //Core Control
    logic [2:0] select_process_i;
    logic start_sobel_i;
    logic start_threshold_i;
    assign select_process_i = ui_in[5:3];
    assign start_sobel_i = ui_in[6];
    assign start_threshold_i = uio_in[6];

  //LFSR Control
    logic LFSR_enable_i;
    logic seed_stop_i;
    logic lfsr_en_i;
    logic lfsr_done;
    logic lfsr_mode_sel_i; 
    assign LFSR_enable_i = uio_in[0];
    assign seed_stop_i = uio_in[1];
    assign lfsr_en_i = uio_in[2];
    assign lfsr_mode_sel_i = uio_in[3];

  //SA Control
    logic sa_en_i;
    logic sa_clear_i;
    logic frame_done_i;
    assign sa_en_i = ui_in[7];
    assign sa_clear_i = uio_in[4];
    assign frame_done_i = uio_in[5];
  

    logic nreset_i; 
    spi_dep_async_nreset_synchronizer nreset_sync0 (
      .clk_i(clk),
      .async_nreset_i(nreset_async_i),
      .tied_value_i(1'b1),
      .nreset_o(nreset_i)
    );

    logic [2:0] select_process_i_sync;
    spi_dep_signal_synchronizer sgnl_sync0 (
      .clk_i(clk),
      .nreset_i(nreset_i),
      .async_signal_i(select_process_i[0]),
      .signal_o(select_process_i_sync[0])
    );

    spi_dep_signal_synchronizer sgnl_sync1 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(select_process_i[1]),
        .signal_o(select_process_i_sync[1])
    );

    spi_dep_signal_synchronizer sgnl_sync2 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(select_process_i[2]),
        .signal_o(select_process_i_sync[2])
    );

    logic start_sobel_i_sync;
        spi_dep_signal_synchronizer sgnl_sync3 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(start_sobel_i),
        .signal_o(start_sobel_i_sync)
    );

    logic start_threshold_i_sync;
        spi_dep_signal_synchronizer sgnl_sync4 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(start_threshold_i),
        .signal_o(start_threshold_i_sync)
    );

    logic LFSR_enable_i_sync;
    spi_dep_signal_synchronizer sgnl_sync5 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(LFSR_enable_i),
        .signal_o(LFSR_enable_i_sync)
    );

    logic seed_stop_i_sync;
    spi_dep_signal_synchronizer sgnl_sync6 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(seed_stop_i),
        .signal_o(seed_stop_i_sync)
    );
    
    logic lfsr_en_i_sync;
    spi_dep_signal_synchronizer sgnl_sync7 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(lfsr_en_i),
        .signal_o(lfsr_en_i_sync)
    );

    logic sa_en_i_sync;
    spi_dep_signal_synchronizer sgnl_sync8 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(sa_en_i),
        .signal_o(sa_en_i_sync)
    );

    logic frame_done_i_sync;
    spi_dep_signal_synchronizer sgnl_sync9 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(frame_done_i),
        .signal_o(frame_done_i_sync)
    );

    logic lfsr_mode_sel_i_sync;
    spi_dep_signal_synchronizer sgnl_sync10 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(lfsr_mode_sel_i),
        .signal_o(lfsr_mode_sel_i_sync)
    );

    logic sa_clear_i_sync;
    spi_dep_signal_synchronizer sgnl_sync11 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .async_signal_i(sa_clear_i),
        .signal_o(sa_clear_i_sync)
    );
    
    logic [MAX_PIXEL_BITS-1:0] input_data;
    logic [MAX_PIXEL_BITS-1:0] output_data;
    
    logic [MAX_PIXEL_BITS-1:0] input_pixel;
    logic [MAX_PIXEL_BITS-1:0] output_px;
    logic [MAX_PIXEL_BITS-1:0] input_lfsr_data;  
    logic [MAX_PIXEL_BITS-1:0] output_lfsr_data;  
    logic [MAX_PIXEL_BITS-1:0] lfsr_out_data;
    
    logic [MAX_PIXEL_BITS-1:0] sa_signature;
        
    logic in_data_rdy;
    logic out_data_rdy;
    logic in_px_rdy;
    logic out_px_rdy;
    logic in_lfsr_rdy;
    logic out_lfsr_rdy;
    logic out_config_rdy;

    assign input_lfsr_data = LFSR_enable_i_sync ? input_data : 24'd0;      
    assign input_pixel = LFSR_enable_i_sync ? lfsr_out_data : input_data;

    assign in_lfsr_rdy = LFSR_enable_i_sync ? in_data_rdy : 1'b0;      
    assign in_px_rdy = LFSR_enable_i_sync ? out_lfsr_rdy : in_data_rdy;

    logic [2:0] LEDs;
    always_ff @(posedge clk) begin
      LEDs <= {sa_en_i_sync, LFSR_enable_i_sync, lfsr_mode_sel_i_sync};
    end 

    always_comb begin
      case({sa_en_i_sync, LFSR_enable_i_sync, lfsr_mode_sel_i_sync})
        // SA mode + LFSR enabled
        3'b110: begin
            output_data  = (lfsr_done & ~lfsr_en_i_sync) ? sa_signature : 24'd0;
            out_data_rdy = lfsr_done;
        end

        // SA mode + LFSR disabled
        3'b100: begin
            output_data  = frame_done_i_sync ? sa_signature : 24'd0;
            out_data_rdy = frame_done_i_sync;
        end

        // !SA mode + LFSR enabled + LFSR mode select=1
        3'b011: begin
            output_data  = output_px;
            out_data_rdy = out_px_rdy;
        end

        // !SA mode + LFSR enabled + LFSR mode select=0
        3'b010: begin
            output_data  = output_lfsr_data;
            out_data_rdy = out_config_rdy;
        end

        // !SA mode + LFSR disabled
        3'b000: begin
            output_data  = output_px;
            out_data_rdy = out_px_rdy;
        end

        default: begin
            output_data  = 24'd0;
            out_data_rdy = 1'b0;
        end
    endcase
  end

    spi_control spi0 (
      .clk_i(clk),
      .nreset_i(nreset_i),
      .spi_sck_i(spi_sck_i),
      .spi_sdi_i(spi_sdi_i),
      .spi_cs_i(spi_cs_i),
      .spi_sdo_o(spi_sdo_o),
      .px_rdy_o_spi_i(out_data_rdy),
      .px_rdy_i_spi_o(in_data_rdy),
      .input_px_gray_o(input_data),
      .output_px_sobel_i(output_data)
    );
    
    top_gray_sobel gray_sobel0 (
      .clk_i(clk),
      .nreset_i(nreset_i),
      .select_i(select_process_i_sync),
      .start_sobel_i(start_sobel_i_sync),
      .start_threshold_i (start_threshold_i_sync), 
      .px_rdy_i(in_px_rdy),
      .in_pixel_i(input_pixel),
      .out_pixel_o(output_px),
      .px_rdy_o(out_px_rdy)
    );
    
    LFSR lfsr0 (
      .clk_i(clk),
      .nreset_i(nreset_i),
      .config_i(seed_stop_i_sync),
      .config_rdy_i(in_lfsr_rdy),
      .config_data_i(input_lfsr_data),
      .config_data_o(output_lfsr_data),
      .config_done_o(out_config_rdy),
      .lfsr_en_i(lfsr_en_i_sync),
      .lfsr_out(lfsr_out_data),
      .lfsr_rdy_o(out_lfsr_rdy),
      .lfsr_done(lfsr_done)
    );


    signature_analyzer sa0 (
        .clk_i(clk),
        .nreset_i(nreset_i),
        .en_i(sa_en_i_sync),          
        .rdy_i(out_px_rdy),  
        .clear_i(sa_clear_i_sync),         
        .data_i(output_px[PIXEL_WIDTH_OUT-1:0]),     
        .signature_o(sa_signature)
    );

    assign uo_out[2:0] = select_process_i_sync;
    assign uo_out[3]   = spi_sdo_o;
    assign uo_out[4]   = lfsr_done;
    assign uo_out[7:5] = LEDs;

endmodule
