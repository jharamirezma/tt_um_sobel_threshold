from concurrent.futures import wait
from pathlib import Path
import numpy as np
import cocotb
import cv2

from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge
from cocotb.triggers import Timer
from matplotlib import pyplot as plt

## Inputs
## spi_cs_i          = ui_in[0]
## spi_sck_i         = ui_in[1]
## spi_sdi_i         = ui_in[2]
## select_i[2:0]     = ui_in[5:3]
## start_sobel_i     = ui_in[6]
## sa_en_i           = ui_in[7]
## LFSR_enable_i     = uio_in[0]
## seed_stop_i       = uio_in[1]
## lfsr_en_i         = uio_in[2]
## lfsr_mode_sel_i   = uio_in[3]
## sa_clear_i        = uio_in[4]
## frame_done_i      = uio_in[5]
## start_threshold_i = uio_in[6]
## (unused)          = uio_in[7]

## Outputs
## uo_out[2:0] = select_process_i_sync
## uo_out[3]   = spi_sdo_o 
## uo_out[4]   = lfsr_done
## uo_out[7:5] = LEDs {sa_en, LFSR_enable, lfsr_mode_sel}

## Select process
## 3'b000 -> RGB  -> Gray -> Sobel -> Threshold
## 3'b001 -> Gray -> Sobel -> Threshold
## 3'b010 -> RGB  -> Gray -> Sobel
## 3'b011 -> Gray -> Sobel
## 3'b100 -> RGB  -> Gray
## 3'b101 -> Bypass

## Select input
## 0 -> SPI pixel
## 1 -> LFSR pixel


# Parameters
RPI_SPI_CLK = 66/22
ADC_SPI_CLK = 50
DUTY_CYCLE = 0.5
STREAM_DATA_WIDTH = 24
clock_period = 1 / ADC_SPI_CLK  # Clock period in seconds
half_period = clock_period * DUTY_CYCLE
PIXEL_SIM = 10   # Number of pixels for testing
select_process = 0

def get_neighbors(input_array, index, width):
    neighbors = []
    x = index % width
    y = index // width

    for i in range(max(0, x - 1), min(width, x + 2)):
        for j in range(max(0, y - 1), min(len(input_array) // width, y + 2)):
            neighbor_index = j * width + i
            neighbors.append(input_array[neighbor_index])
    return neighbors


def get_neighbor_array(image, input_array):
    height, width, _ = image.shape
    array_neighbors = []
    neighbor_count = 0 
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            i = y * width + x
            neighbors = get_neighbors(input_array, i, width)
            array_neighbors.append(neighbors)
            neighbor_count += 1
    return array_neighbors

def gray_convertion(data):
    red = (data >> 16) & 0xFF
    green = (data >> 8) & 0xFF
    blue = data & 0xFF
    result = (red>>2)+(red>>5)+(green>>1)+(green>>4)+(blue>>4)+(blue>>5)
    return result

def lfsr_sequence(seed, n_steps=100):
    lfsr = seed
    sequence = [lfsr]
    for _ in range(n_steps-1):
        bit = ~(( (lfsr >> 12) & 1) ^ ((lfsr >> 3) & 1)) & 1
        lfsr = ((lfsr << 1) & 0xFFFFFF) | bit  # 24 bits
        sequence.append(lfsr)
    return sequence



#-------------------------------Convert RGB image to grayscale------------------------------------------
img_original = cv2.imread('test_images/tenis_320x240.png', cv2.IMREAD_COLOR) 
img_original = cv2.cvtColor(img_original, cv2.COLOR_BGR2RGB)

array_input_image = []

if select_process == 1:
    gray_opencv = cv2.cvtColor(img_original, cv2.COLOR_RGB2GRAY) 
    input_image = gray_opencv
    for i in range(0,240): 
        for j in range(0,320):
            pixel = input_image[i][j]
            array_input_image.append(f'{pixel:08b}')
else:
    input_image = img_original
    for i in range(0,240): 
        for j in range(0,320):
            pixel = input_image[i][j]
            array_input_image.append(f"{pixel[0]:08b}{pixel[1]:08b}{pixel[2]:08b}")
#----------------------------------------cocotb test bench----------------------------------------------
#reset
async def reset_dut(dut, duration_ns):
    dut.rst_n.value = 0
    await Timer(duration_ns, units="ns")
    dut.rst_n.value = 1
    dut.rst_n._log.debug("Reset complete")

#clock
#@cocotb.coroutine
async def clock_generator(dut):
    # Infinite loop to generate the clock
    while True:
        dut.clk <= 0
        await Timer(half_period, units="ns")
        dut.clk <= 1
        await Timer(half_period, units="ns")

#spi transfer data 
def swap_bytes(data):
    byte3 = (data >> 16) & 0xFF
    byte2 = (data >> 8) & 0xFF
    byte1 = data & 0xFF
    return (byte1 << 16) | (byte2 << 8) | byte3

async def spi_transfer_pi(data, dut):
    data_tx_rpi = 0
    data_rx_rpi = 0
    await Timer(3)

    # Poner cs=0, sck=1, sdi=0 sin tocar los demás bits
    dut.ui_in.value = (int(dut.ui_in.value) & ~0x07) | 0x02  # cs=0, sck=1, sdi=0
    data_tx_rpi = swap_bytes(data)

    for i in range(STREAM_DATA_WIDTH):
        sdi = (data_tx_rpi >> (STREAM_DATA_WIDTH - 1 - i)) & 0x01
        dut.ui_in.value = (int(dut.ui_in.value) & ~0x07) | (sdi << 2)  # sck=0, sdi=bit
        await Timer(RPI_SPI_CLK)
        try:
            uo_val = int(dut.uo_out.value)
            read_bit = (uo_val >> 3) & 1
        except ValueError:
            read_bit = 0
        data_rx_rpi = int(read_bit << (STREAM_DATA_WIDTH - 1 - i)) + data_rx_rpi
        dut.ui_in.value = (int(dut.ui_in.value) & ~0x03) | 0x02  # sck=1
        await Timer(RPI_SPI_CLK)
   
    for _ in range(6):
        await Timer(RPI_SPI_CLK)

    return swap_bytes(data_rx_rpi)

async def spi_transfer_chunk(pixel_list, dut):
    """Envía una lista de píxeles en un solo bloque SPI sin soltar CS"""
    results = []
    
    await Timer(3)
    # CS=0 una sola vez para todo el chunk
    dut.ui_in.value = (int(dut.ui_in.value) & ~0x07) | 0x02  # cs=0, sck=1, sdi=0

    for pixel in pixel_list:
        data_tx = swap_bytes(int(pixel, 2))
        data_rx = 0

        for i in range(STREAM_DATA_WIDTH):
            sdi = (data_tx >> (STREAM_DATA_WIDTH - 1 - i)) & 0x01
            dut.ui_in.value = (int(dut.ui_in.value) & ~0x07) | (sdi << 2)
            await Timer(RPI_SPI_CLK)
            try:
                read_bit = (int(dut.uo_out.value) >> 3) & 1
            except ValueError:
                read_bit = 0
            data_rx |= read_bit << (STREAM_DATA_WIDTH - 1 - i)
            dut.ui_in.value = (int(dut.ui_in.value) & ~0x03) | 0x02
            await Timer(RPI_SPI_CLK)

        # Pausa entre palabras pero SIN soltar CS
        for _ in range(6):
            await Timer(RPI_SPI_CLK)

        results.append(swap_bytes(data_rx))

    return results

async def int_to_bytes_le(val, n_bytes):
    return [(val >> (8*i)) & 0xFF for i in range(n_bytes)]
 
# Wait until output file is completely written
async def wait_file():
    Path('output_image_sobel.txt').exists()

# Parallel check of px_rdy_o and px_out
async def monitor_px_rdy(dut, array):
    mask_7 = 1 << 7
    px_rdy_o = (dut.uio_out.value.integer & mask_7) >> 7
    while True:
        await RisingEdge(px_rdy_o)
        await FallingEdge(px_rdy_o)
    #     #array.append(px_out.value)
    #     px_rdy_high_count += 1

# #Bypass Test For SPI Data!
@cocotb.test()
async def tt_um_gray_sobel_bypass(dut):
    # Clock cycle
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1
    # Initial
    dut.ena.value = 0
    dut.ui_in.value = 0

    # Selection = 3
    dut.ui_in.value = (1 << 3) | (1 << 5) | (1 << 1) | (1 << 0)
    
    # NOT LFSR
    dut.uio_in.value = 0   
    
    N = 5
    random_numbers_array = np.random.randint(0, 2**24, N, dtype=np.uint32)
    await reset_dut(dut, 200)

    await FallingEdge(dut.clk)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)
    await Timer(20)
    for i, data in enumerate(random_numbers_array):
        read_data = await spi_transfer_pi(int(data), dut)
        if i > 0:
            cocotb.log.info(f"{i}) output: {read_data:x} input: {random_numbers_array[i-1]:x}")
            assert read_data == random_numbers_array[i-1]
    
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)


# Only Gray test
@cocotb.test()
async def tt_um_gray_sobel_gray(dut):
    # Clock cycle
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1
    # Initial
    dut.ena.value = 0
    dut.ui_in.value = 0

    # Selection = 2 --> Only gray
    dut.ui_in.value = (1 << 5) | (1 << 0) | (1 << 1)
    
    # NOT LFSR
    dut.uio_in.value = 0
    
    N = 10
    random_numbers_array = np.random.randint(0, 2**24, N, dtype=np.uint32)

    await reset_dut(dut, 200)

    await FallingEdge(dut.clk)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)
    await Timer(20)
    for i, data in enumerate(random_numbers_array):
        read_data = await spi_transfer_pi(int(data), dut)
        if i > 0:
            cocotb.log.info(f"{i} RGB: {data:#x}")
            cocotb.log.info(f"{i} Gray HW output: {read_data:#x} Expected: {gray_convertion(random_numbers_array[i-1]):#x}")
            assert read_data == gray_convertion(random_numbers_array[i-1])
    
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)


# Only sobel test 
@cocotb.test()
async def tt_um_gray_sobel_sobel(dut):
    # Clock cycle
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1
    # Initial
    dut.ena.value = 0
    dut.ui_in.value = 0

    # Selection = 1 --> Only sobel
    dut.ui_in.value = (1 << 3) | (1 << 4) | (1 << 0) | (1 << 1) | (1 << 6)
    
    # NOT LFSR
    dut.uio_in.value = 0

    pixel_gray_array = [82, 82, 77, 82, 83, 80, 84, 86, 83, 87, 88, 
                        85, 87, 88, 85, 88, 92, 96, 100, 112, 122, 
                        117, 132, 146, 125, 146, 162, 122, 145, 164, 
                        123, 147, 168, 123, 147, 169]

    await reset_dut(dut, 200)

    await FallingEdge(dut.clk)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)
    await Timer(20)

    for i, data in enumerate(pixel_gray_array[:36]):
        read_data = await spi_transfer_pi(int(data), dut)
        received_bytes = await int_to_bytes_le(read_data, 5)
        cocotb.log.info(f"Pixel {i} sended: {data}")

        if i >= 9 and (i - 9) % 3 == 0:
            cocotb.log.info(f"Convolution output: {((i - 9) // 3) + 1}: {received_bytes}")


    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)

# Gray + sobel test 
@cocotb.test()
async def tt_um_gray_sobel_gray_sobel(dut):
    # Clock cycle
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1
    # Initial
    dut.ena.value = 0
    dut.ui_in.value = 0

    # Selection = 0 --> Gray + Sobel
    dut.ui_in.value =  (1 << 4) | (1 << 0) | (1 << 1) | (1 << 6)  #spi_cs_i, spi_sck_i, start_sobel_i
    
    # NOT LFSR
    dut.uio_in.value = 0
    
    N = 4
    pixel_rgb_array = [7035430, 7100705, 6968596, 7035426, 7232288, 7231766, 7364126, 7561244, 7560466,  7561756, 
                        7693081, 7626512, 7627029, 7692821, 7626510, 7758615, 8218396, 8481310, 8809771, 9665080, 
                        10257217, 10058820, 11242839, 12098150, 10715737, 12228722, 13346952, 10714975, 12293755,
                        13609366, 10845029, 12424322, 13872035, 10779236, 12555396, 14134184, 11041889, 12555393, 
                        14068645, 11239518, 12686716, 13805213, 11568475, 12686964, 13476497, 11961693, 12948596, 
                        13409675, 13141873, 13011059, 13077630, 13272948, 12549740, 11498596, 12749166, 11696737, 
                        9987148, 12026981, 11105879, 9462083, 11303258, 10316876, 8870199, 10841941, 9789251, 
                        8408621]

    no_rtl_result = []

    await reset_dut(dut, 200) 

    await FallingEdge(dut.clk)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0) #spi_cs_i
    await Timer(20)

    for i, data in enumerate(pixel_rgb_array[:36]):
        read_data = await spi_transfer_pi(int(data), dut)
        received_bytes = await int_to_bytes_le(read_data, 5)
        cocotb.log.info(f"Pixel {i} sended: {int(data)}")

        if i >= 9 and (i - 9) % 3 == 0:
            cocotb.log.info(f"Convolution output: {((i - 9) // 3) + 1}: {received_bytes}")

    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)  #spi_cs_i
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)  #spi_cs_i

def expected_sa(data_list, width=24):
    sa = 0
    for val in data_list:
        for i in range(width):
            sa ^= (val >> i) & 0x1
    return sa

# Seed Stop LFSR + Gray + SA test
@cocotb.test()
async def tt_um_gray_sobel_lfsr_sa(dut):
    # Clock cycle
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1
    # Initial
    dut.ena.value = 0
    dut.ui_in.value = 0

    # Selection = 2 --> Only gray
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 5) | (1 << 1) | (1 << 7)  # select, CS active, SA enable

    # LFSR: Enable and enable seed/stop load
    dut.uio_in.value = 0b00000001  # Enable LFSR, rest disabled

    seed = 0xF37571

    # --- Load seed and stop via SPI ---
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)  # CS active

    await spi_transfer_pi(seed, dut)
    await Timer(20)

    stop = 0xD5C501
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 1)   # stop load enable
    await spi_transfer_pi(stop, dut)
    await Timer(20)

    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 1)  # seed_stop disable

    # --- Enable LFSR ---
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 2)  # lfsr_en_i enabled
    await Timer(20)

    # --- Wait lfsr_done is enabled ---
    while True:
        try:
            if (int(dut.uo_out.value) >> 4) & 1:
                break
        except ValueError:
            pass
        await RisingEdge(dut.clk)

    # --- Explicit Stop LFSR ---
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 2)

    # --- Read final SA ---
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)  # CS active
    await Timer(20)
    read_data = await spi_transfer_pi(0, dut)  # dummy for reading signature_o
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)  # CS disable

    cocotb.log.info(f"Final signature SA: {read_data:x}")

    dut.uio_in.value = int(dut.uio_in.value) | (1 << 4)
    await Timer(20)
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 4)
    await RisingEdge(dut.clk)

# # Gray + sobel test image
# @cocotb.test()
# async def tt_um_gray_sobel_gray_sobel_img(dut):
#     # Clock cycle
#     cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

#     # dut.VGND.value = 0
#     # dut.VPWR.value = 1
#     # Inital
#     dut.ena.value = 0
#     dut.ui_in.value = 0

#     # Selection = 0 --> Gray + Sobel
#     dut.ui_in.value =  (1 << 4) |(1 << 0) | (1 << 1) | (1 << 6)  #spi_cs_i, spi_sck_i, start_sobel_i
    
#     # NOT LFSR
#     dut.uio_in.value = 0
    
#     N = 4

#     no_rtl_result = []

#     await reset_dut(dut, 20) 

#     await FallingEdge(dut.clk)
#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0) #spi_cs_i
#     await Timer(20)


#     array_neighbors = get_neighbor_array(img_original, array_input_image)

#     # for i, data in enumerate(pixel_rgb_array[:4]):
#     #     cocotb.log.info(f"Pixel {i} RGB: {[int(b, 2) for b in data]}")
#     output_pixels = []
#     counter_pixels = 0

#     CHUNK_SIZE = 1024

#     for i, neighbors in enumerate(array_neighbors):
#         if i%10000 == 0:
#             cocotb.log.info(f'Pixels:{i}')
       
#         pixel_list = neighbors if i == 0 else neighbors[6:]

#         for chunk_start in range(0, len(pixel_list), CHUNK_SIZE):
#             chunk = pixel_list[chunk_start:chunk_start + CHUNK_SIZE]
#             read_data_list = await spi_transfer_chunk(chunk, dut)

#             for read_data in read_data_list:
#                 if counter_pixels >= 9 and (counter_pixels - 9) % 3 == 0:
#                     received_bytes = await int_to_bytes_le(read_data, 5)
#                     output_pixels.append(received_bytes[0])
#                 counter_pixels += 1
#         await Timer(20)

#     with open('output_image.txt', 'w') as file_out:
#         for pixel_p in output_pixels:
#             file_out.write(f"{pixel_p}\n")

#     # read file
    
#     if select_process == 3:
#         with open('output_image.txt', 'r') as f: 
#             out_hw_txt = f.read().splitlines()

#         array_out = np.array(out_hw_txt)

#         encode_image = []
#         for ind, pixel in enumerate(array_out):
#             value = int(pixel, 2)
#             red = ((value >> 16) & 0xFF)
#             green = ((value >> 8) & 0xFF)
#             blue = (value & 0xFF)
#             row = [red, green, blue]
#             encode_image.append(row)
#         array_out_reshape = np.reshape(encode_image, (240, 320, 3))        
#     else:
#         with open('output_image.txt', 'r') as f: 
#             out_hw_txt = f.read().splitlines()  

#         # Arrange pixels
#         array_out = np.array(out_hw_txt)
#         if select_process == 2:
#             array_out_reshape = np.reshape(array_out, (240, 320))
#         else:   
#             array_out_reshape = np.reshape(array_out, (240-2, 320-2))
        
#     array_out = array_out_reshape.astype(np.uint8)
#     cv2.imwrite('output_image.jpg', array_out)
#     out_image = cv2.imread('output_image.jpg')
#     plt.imshow(out_image)
#     plt.show()
            

#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)  #spi_cs_i
#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)  #spi_cs_i


#Gray + Sobel + Threshold test image
# @cocotb.test()
# async def tt_um_gray_sobel_gray_sobel_threshold_img(dut):
#     # Clock cycle
#     cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

#     # Initial
#     dut.ena.value = 0
#     dut.ui_in.value = 0

#     # Selection = 3'b000 --> Gray + Sobel + Threshold
#     # ui_in[5:3] = 000, start_sobel_i = ui_in[6] = 1
#     dut.ui_in.value = (1 << 0) | (1 << 1) | (1 << 6)  # spi_cs_i, spi_sck_i, start_sobel_i
#     #                  ui_in[3:5] = 000 → select = 3'b000 (already 0)

#     # NOT LFSR, start_threshold_i = uio_in[6] = 1
#     dut.uio_in.value = (1 << 6)  # start_threshold_i active

#     no_rtl_result = []

#     await reset_dut(dut, 20)

#     await FallingEdge(dut.clk)
#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)  # spi_cs_i active
#     await Timer(20)

#     array_neighbors = get_neighbor_array(img_original, array_input_image)

#     output_pixels = []
#     counter_pixels = 0

#     CHUNK_SIZE = 1024

#     for i, neighbors in enumerate(array_neighbors):
#         if i % 10000 == 0:
#             cocotb.log.info(f'Pixels: {i}')

#         pixel_list = neighbors if i == 0 else neighbors[6:]

#         for chunk_start in range(0, len(pixel_list), CHUNK_SIZE):
#             chunk = pixel_list[chunk_start:chunk_start + CHUNK_SIZE]
#             read_data_list = await spi_transfer_chunk(chunk, dut)

#             for read_data in read_data_list:
#                 if counter_pixels >= 9 and (counter_pixels - 9) % 3 == 0:
#                     received_bytes = await int_to_bytes_le(read_data, 5)
#                     # Output is binary: 0 or 255
#                     output_pixels.append(received_bytes[0])
#                 counter_pixels += 1
#         await Timer(20)

#     dummy = await spi_transfer_pi(0, dut)
#     received_bytes = await int_to_bytes_le(dummy, 5)
#     output_pixels.append(received_bytes[0])

#     with open('output_image_threshold.txt', 'w') as file_out:
#         for pixel_p in output_pixels:
#             file_out.write(f"{pixel_p}\n")

#     # Read and save image
#     with open('output_image_threshold.txt', 'r') as f:
#         out_hw_txt = f.read().splitlines()

#     array_out = np.array(out_hw_txt).astype(np.uint8)
#     array_out_reshape = np.reshape(array_out, (240 - 2, 320 - 2))

#     cv2.imwrite('output_image_threshold.jpg', array_out_reshape)
#     out_image = cv2.imread('output_image_threshold.jpg')
#     plt.imshow(out_image, cmap='gray')
#     plt.title('Gray + Sobel + EMA Threshold')
#     plt.show()

#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)   # spi_cs_i disable
#     await Timer(20)
#     dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)

@cocotb.test()
async def tt_um_gray_sobel_gray_sobel_threshold(dut):
    cocotb.start_soon(Clock(dut.clk, 2 * half_period, units="ns").start())

    # dut.VGND.value = 0
    # dut.VPWR.value = 1

    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.ui_in.value = (1 << 0) | (1 << 1) | (1 << 6)
    dut.uio_in.value = (1 << 6)

    N_WINDOWS = 50

    await reset_dut(dut, 200)
    await FallingEdge(dut.clk)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << 0)
    await Timer(20)

    array_neighbors = get_neighbor_array(img_original, array_input_image)

    output_pixels = []
    counter_pixels = 0
    CHUNK_SIZE = 1024

    for i, neighbors in enumerate(array_neighbors[:N_WINDOWS]):
        pixel_list = neighbors if i == 0 else neighbors[6:]

        for chunk_start in range(0, len(pixel_list), CHUNK_SIZE):
            chunk = pixel_list[chunk_start:chunk_start + CHUNK_SIZE]
            read_data_list = await spi_transfer_chunk(chunk, dut)

            for read_data in read_data_list:
                if counter_pixels >= 9 and (counter_pixels - 9) % 3 == 0:
                    received_bytes = await int_to_bytes_le(read_data, 5)
                    output_pixels.append(received_bytes[0])
                counter_pixels += 1
        await Timer(20)

    dummy = await spi_transfer_pi(0, dut)
    received_bytes = await int_to_bytes_le(dummy, 5)
    output_pixels.append(received_bytes[0])

    cocotb.log.info(f"Output pixels: {len(output_pixels)}")
    cocotb.log.info(f"Values: {output_pixels}")

    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)
    await Timer(20)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << 0)