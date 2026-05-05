`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif

module LFSR(
        input logic clk_i, 
        input logic nreset_i, 
        input logic config_i,
        
        input logic config_rdy_i, 
        input logic [MAX_PIXEL_BITS-1:0] config_data_i,
        output logic config_done_o,
        output logic [MAX_PIXEL_BITS-1:0] config_data_o,
        
        input logic lfsr_en_i,
        output logic [MAX_PIXEL_BITS-1:0] lfsr_out,
        output logic lfsr_rdy_o,
        output logic lfsr_done
    );

    logic [MAX_PIXEL_BITS-1:0] seed_reg;
    logic [MAX_PIXEL_BITS-1:0] stop_reg;
    
    assign config_data_o = config_i ? stop_reg : seed_reg;

    always@(posedge clk_i or negedge nreset_i) begin
        if(!nreset_i) begin 
            seed_reg <= 24'd0;
            stop_reg <= 24'd0;
            config_done_o <= 1'b0;
        end else begin 
            config_done_o <= config_rdy_i; 
            case({config_i,config_rdy_i})
                2'b01: seed_reg <= config_data_i;
                2'b11: stop_reg <= config_data_i;
                default: begin
                    seed_reg <= seed_reg;
                    stop_reg <= stop_reg;
                end
            endcase
        end
    end
    
    logic r_xnor;
    logic stop_done;
    
    always_ff @(posedge clk_i or negedge nreset_i) begin
        if(!nreset_i) begin
            lfsr_out <= 24'd0;
            lfsr_rdy_o <= 1'b0;
        end else begin
            if (lfsr_en_i & ~stop_done) begin
              lfsr_out <= {lfsr_out[MAX_PIXEL_BITS-2:0], r_xnor};
                lfsr_rdy_o <= 1'b1;
           end else if(stop_done) begin
                lfsr_out <= lfsr_out;
                lfsr_rdy_o <= 1'b0;
           end else begin
                lfsr_out <= seed_reg;
                lfsr_rdy_o <= 1'b0;
           end
        end
    end

    always_comb begin
       r_xnor = lfsr_out[12] ^~ lfsr_out[3];
    end

    assign stop_done =(lfsr_out[MAX_PIXEL_BITS-1:0] == stop_reg) ? 1'b1 : 1'b0;
    assign lfsr_done = stop_done;

endmodule