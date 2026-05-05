`ifdef COCOTB_SIM
  `include "../src/parameters.svh"
`else
  `include "parameters.svh"
`endif

module signature_analyzer(
    input  logic clk_i,
    input  logic nreset_i,
    input  logic en_i,                    
    input  logic rdy_i,   
    input  logic clear_i,                 
    input  logic [PIXEL_WIDTH_OUT-1:0] data_i, 
    output logic [MAX_PIXEL_BITS-1:0] signature_o  
);

    logic [MAX_PIXEL_BITS-1:0] signature_q;

    always_ff @(posedge clk_i or negedge nreset_i) begin
        if (!nreset_i) begin
            signature_q <= 24'd0;
        end else if (clear_i) begin
            signature_q <= 24'd0;  
        end else if (en_i && rdy_i) begin
            signature_q <= {signature_q[MAX_PIXEL_BITS-2:0], 1'b0} 
                           ^ {{(MAX_PIXEL_BITS-PIXEL_WIDTH_OUT){1'b0}}, data_i};
        end
    end

    assign signature_o = signature_q;

endmodule
