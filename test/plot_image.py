import numpy as np
import cv2
from matplotlib import pyplot as plt
 
    # read file
select_process = 0
if select_process == 3:
    with open('output_image_threshold.txt', 'r') as f: 
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
    with open('output_image_threshold.txt', 'r') as f: 
        out_hw_txt = f.read().splitlines()  
    # Arrange pixels
    array_out = np.array(out_hw_txt)
    if select_process == 2:
        array_out_reshape = np.reshape(array_out, (240, 320))
    else:   
        array_out_reshape = np.reshape(array_out, (240-2, 320-2))
    
array_out = array_out_reshape.astype(np.uint8)
cv2.imwrite('output_image_threshold.jpg', array_out)
out_image = cv2.imread('output_image_threshold.jpg')
plt.imshow(out_image)
plt.show()
        