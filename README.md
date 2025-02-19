# Image-Processing-Using-Verilog
This project is a Verilog-implemented image processing module that reads and processes image data. The module supports a number of image processing functions, such as thresholding, saturation modification, inversion, and brightness modification. 
**#image_processor**
This image processing module that reads an image from a file, processes it pixel by pixel, and outputs the processed image data along with synchronization signals (VSYNC and HSYNC). It supports several image processing operations, including brightness adjustment, color inversion, thresholding, and saturation adjustment.
The module stores the image data in memory after reading it from the input file,the image is flipped vertically to prepare it for processing
Processing:
The reading, processing, and output of pixel data are all managed by a finite state machine (FSM).
The module applies the chosen image processing actions (brightness, inversion, thresholding, or saturation) to two pixels at a time.
**imae_write**
Pixel data from an input stream is captured by the image_write Verilog module and written to a BMP image file.
It receives horizontal sync (hsync) signals and pixel data (two RGB values at a time,For efficiency, two pixels are handled per clock cycle.),synchronizes using a clock (HCLK) and reset (HRESETn),stores pixel data in a buffer after capturing it after each hsync pulse.
,arranges the pixel data using the BMP format (BGR color layout, bottom-up order),,It writes the data, together with a 54-byte BMP header, to a BMP file after all the pixels have been collected.
**output images**
increased brightness
![brightness_addition](https://github.com/user-attachments/assets/883b251c-ea71-434f-8639-ebd6484e32c9)


