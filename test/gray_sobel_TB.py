from pathlib import Path
import numpy as np
import cocotb
import cv2

from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge
from cocotb.triggers import Timer
from matplotlib import pyplot as plt


select = 0

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

#-------------------------------Convert RGB image to grayscale------------------------------------------
img_original = cv2.imread('../test_images/monarch_RGB.jpg', cv2.IMREAD_COLOR) 
img_original = cv2.cvtColor(img_original, cv2.COLOR_BGR2RGB)

array_input_image = []

if select == 1:
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


with open('input_pixels.txt', 'w') as f:
    for pixel in array_input_image:
        f.write(f"{int(str(pixel), 2)}\n")
#----------------------------------------cocotb test bench----------------------------------------------
# Reset
async def reset_dut(dut, duration_ns):
    dut.nreset_i.value = 0
    await Timer(duration_ns, units="ns")
    dut.nreset_i.value = 1
    dut.nreset_i._log.debug("Reset complete")

# Wait until output file is completely written
async def wait_file():
    Path('output_image_sobel.txt').exists()

# Parallel check of px_rdy_o and px_out
async def monitor_px_rdy(px_rdy_o, array_output, px_out):
    while True:
        await RisingEdge(px_rdy_o)
        await FallingEdge(px_rdy_o)
        array_output.append(px_out.value)

@cocotb.test()
async def gray_sobel_TB(dut):

    # Clock cycle
    clock = Clock(dut.clk_i, 20, units="ns") 
    cocotb.start_soon(clock.start(start_high=False))

    # Inital
    dut.in_pixel_i.value = 0
    dut.start_sobel_i.value = 0
    dut.select_i.value = 0
    dut.px_rdy_i.value = 0

    # Store processed pixels
    array_output_image = []

    # Get px_rdy_o signal DUT (Device Under Test)
    px_rdy_o = dut.px_rdy_o
    px_out = dut.out_pixel_o

    # Start the process to monitor the px_rdy_o signal in parallel
    cocotb.start_soon(monitor_px_rdy(px_rdy_o, array_output_image, px_out))
    
    await reset_dut(dut, 10)    

    # await FallingEdge(dut.clk_i)
    dut.select_i.value = select

    if select == 2 or  select == 3:
        dut.start_sobel_i.value = 0
        for ind, pixel in enumerate(array_input_image):
            await FallingEdge(dut.clk_i)
            dut.px_rdy_i.value = 1
            await FallingEdge(dut.clk_i)
            dut.px_rdy_i.value = 0
            dut.in_pixel_i.value = int(pixel, 2)
            if ind%10000 == 0:
                dut._log.info(f'Processed pixels: {ind}')
    else:
        dut.start_sobel_i.value = 1
        array_neighbors = get_neighbor_array(img_original, array_input_image)
        firts_neighbors = array_neighbors[0]
        
        for ind, pixel in enumerate(firts_neighbors):
            await FallingEdge(dut.clk_i)
            dut.px_rdy_i.value = 1
            await FallingEdge(dut.clk_i)
            dut.px_rdy_i.value = 0
            dut.in_pixel_i.value = int(pixel, 2)
    
        for i, neighbor_array in enumerate(array_neighbors[1:]):
            for ind, pixel in enumerate(neighbor_array[6:]):
                await FallingEdge(dut.clk_i)
                dut.px_rdy_i.value = 1
                await FallingEdge(dut.clk_i)
                dut.in_pixel_i.value = int(pixel, 2)
                dut.px_rdy_i.value = 0
            if i%10000 == 0:
                dut._log.info(f'Processed pixels: {i}')
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.px_rdy_i.value = 1
    await FallingEdge(dut.clk_i)
    dut.start_sobel_i.value = 0

    # Write output array into txt file
    if select == 3:
        with open('output_image.txt', 'w') as file_out:
            for pixel in array_output_image:
                file_out.write(f"{pixel}\n")

    else:
        with open('output_image.txt', 'w') as file_out:
            for pixel in array_output_image:
                file_out.write(f"{int(str(pixel), 2)}\n")

    # ############### Read test bench output ####################
    await wait_file() # Wait until output file is completely written

    # read file
    
    if select == 3:
        with open('output_image.txt', 'r') as f: 
            out_hw_txt = f.read().splitlines()

        array_out = np.array(out_hw_txt)

        encode_image = []
        for ind, pixel in enumerate(array_out):
            value = int(pixel, 2)
            red = ((value >> 16) & 0xFF)
            green = ((value >> 8) & 0xFF)
            blue = (value & 0xFF)
            row = [red, green, blue]
            encode_image.append(row)
        array_out_reshape = np.reshape(encode_image, (240, 320, 3))        
    else:
        with open('output_image.txt', 'r') as f: 
            out_hw_txt = f.read().splitlines()  

        # Arrange pixels
        array_out = np.array(out_hw_txt)
        if select == 2:
            array_out_reshape = np.reshape(array_out, (240, 320))
        else:   
            array_out_reshape = np.reshape(array_out, (240-2, 320-2))
        
    array_out = array_out_reshape.astype(np.uint8)
    cv2.imwrite('output_image.jpg', array_out)
    out_image = cv2.imread('output_image.jpg')
    plt.imshow(out_image)
    plt.show()