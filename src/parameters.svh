`ifndef __CONSTANTS_SOBEL__
`define __CONSTANTS_SOBEL__

localparam MAX_PIXEL_BITS = 24;              
localparam PIXEL_WIDTH_OUT = 8;
localparam SOBEL_COUNTER_MAX_BITS = 4;                              //Counter for 3x3 matrix of pixels to convolve with kernel
localparam MAX_GRADIENT_WIDTH = 10;                                 //Max value of gradient could be a sum of three max values of 2^(PIXEL WIDTH) bits
localparam MAX_PIXEL_VAL = 1<< PIXEL_WIDTH_OUT;                     //Binarization max value
localparam MAX_GRADIENT_SUM_WIDTH = 11;    
localparam MAX_RESOLUTION_BITS = 24;
localparam ZERO_PAD_WIDTH = MAX_PIXEL_BITS - PIXEL_WIDTH_OUT;

`endif
