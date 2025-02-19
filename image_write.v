`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: image_write
// Description: Captures pixel data on each horizontal sync and writes a BMP file.
//////////////////////////////////////////////////////////////////////////////////
module image_write #(
    parameter WIDTH = 384,           // Image width  
    parameter HEIGHT = 256,          // Image height  
    parameter INFILE = "output.bmp", // Output file name  
    parameter BMP_HEADER_NUM = 54    // BMP header size  
) (
    input HCLK,                    // Clock input  
    input HRESETn,                 // Active-low reset  
    input hsync,                   // Hsync pulse  
    input [7:0] DATA_WRITE_R0,     // Red 8-bit data (odd)  
    input [7:0] DATA_WRITE_G0,     // Green 8-bit data (odd)   
    input [7:0] DATA_WRITE_B0,     // Blue 8-bit data (odd)   
    input [7:0] DATA_WRITE_R1,     // Red 8-bit data (even)  
    input [7:0] DATA_WRITE_G1,     // Green 8-bit data (even)  
    input [7:0] DATA_WRITE_B1,     // Blue 8-bit data (even)  
    output reg Write_Done          // File write done flag  
);

// File descriptor and loop index  
integer fd, i;  

// BMP header definition  
reg [7:0] BMP_header [0:BMP_HEADER_NUM-1];  

// Output BMP data array  
reg [7:0] out_BMP [0:WIDTH*HEIGHT*3-1];  

// Initialize BMP header (Windows BMP files begin with a 54-byte header)
initial begin  
    BMP_header[ 0] = 66;      BMP_header[28] = 24;  
    BMP_header[ 1] = 77;      BMP_header[29] = 0;  
    BMP_header[ 2] = 54;      BMP_header[30] = 0;  
    BMP_header[ 3] = 0;       BMP_header[31] = 0;  
    BMP_header[ 4] = 18;      BMP_header[32] = 0;  
    BMP_header[ 5] = 0;       BMP_header[33] = 0;  
    BMP_header[ 6] = 0;       BMP_header[34] = 0;  
    BMP_header[ 7] = 0;       BMP_header[35] = 0;  
    BMP_header[ 8] = 0;       BMP_header[36] = 0;  
    BMP_header[ 9] = 0;       BMP_header[37] = 0;  
    BMP_header[10] = 54;     BMP_header[38] = 0;  
    BMP_header[11] = 0;      BMP_header[39] = 0;  
    BMP_header[12] = 0;      BMP_header[40] = 0;  
    BMP_header[13] = 0;      BMP_header[41] = 0;  
    BMP_header[14] = 40;     BMP_header[42] = 0;  
    BMP_header[15] = 0;      BMP_header[43] = 0;  
    BMP_header[16] = 0;      BMP_header[44] = 0;  
    BMP_header[17] = 0;      BMP_header[45] = 0;  
    BMP_header[18] = WIDTH & 8'hFF;  
    BMP_header[19] = (WIDTH >> 8) & 8'hFF;  
    BMP_header[20] = (WIDTH >> 16) & 8'hFF;  
    BMP_header[21] = (WIDTH >> 24) & 8'hFF;  
    BMP_header[22] = HEIGHT & 8'hFF;  
    BMP_header[23] = (HEIGHT >> 8) & 8'hFF;  
    BMP_header[24] = (HEIGHT >> 16) & 8'hFF;  
    BMP_header[25] = (HEIGHT >> 24) & 8'hFF;  
    BMP_header[26] = 1;      
    BMP_header[27] = 0;  
end  

// Counters for pixel capture
integer pixel_count; // counts pairs of pixels (each hsync captures two pixels)
integer row_num, col_num, pixel_index;

always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        pixel_count <= 0;
        Write_Done  <= 1'b0;
    end else begin
        if (hsync && !Write_Done) begin
            // Determine row and column for storing pixels (BMP uses bottom-up order)
            row_num = HEIGHT - (pixel_count / (WIDTH/2)) - 1;
            col_num = (pixel_count % (WIDTH/2)) * 6;  // two pixels per hsync, each pixel = 3 bytes

            // Compute starting index for the two pixels in the out_BMP array
            pixel_index = (row_num * WIDTH * 3) + col_num;

            // Store RGB values (note: BMP uses BGR order)
            out_BMP[pixel_index    ] = DATA_WRITE_B0;  // Blue (Odd)
            out_BMP[pixel_index + 1] = DATA_WRITE_G0;  // Green (Odd)
            out_BMP[pixel_index + 2] = DATA_WRITE_R0;  // Red (Odd)
            out_BMP[pixel_index + 3] = DATA_WRITE_B1;  // Blue (Even)
            out_BMP[pixel_index + 4] = DATA_WRITE_G1;  // Green (Even)
            out_BMP[pixel_index + 5] = DATA_WRITE_R1;  // Red (Even)

            // Optional display message for debugging
            $display("Row %0d Col %0d: R0=%d, G0=%d, B0=%d | R1=%d, G1=%d, B1=%d",
                row_num, col_num, DATA_WRITE_R0, DATA_WRITE_G0, DATA_WRITE_B0,
                DATA_WRITE_R1, DATA_WRITE_G1, DATA_WRITE_B1
            );

            pixel_count <= pixel_count + 1;

            // Check if all pixel pairs have been captured
            if (pixel_count == ((WIDTH * HEIGHT) / 2) - 1) begin
                Write_Done <= 1'b1;
                $display("Write Done Set to 1");
            end
        end
    end
end

//---------------------------------------------------------//
//-------------- Write BMP File to Disk -----------------//
//---------------------------------------------------------//

// Open file for writing at simulation start
initial begin  
    fd = $fopen(INFILE, "wb+");  
end  

// When Write_Done is asserted, write the BMP header and pixel data.
always @(posedge HCLK) begin
    if (Write_Done) begin
        // Write header bytes
        for (i = 0; i < BMP_HEADER_NUM; i = i + 1) begin  
            $fwrite(fd, "%c", BMP_header[i]);
        end  

        // Write pixel data; increment index by 6 (two pixels per iteration)
        for (i = 0; i < WIDTH * HEIGHT * 3; i = i + 6) begin  
            $fwrite(fd, "%c", out_BMP[i  ]);
            $fwrite(fd, "%c", out_BMP[i+1]);
            $fwrite(fd, "%c", out_BMP[i+2]);
            $fwrite(fd, "%c", out_BMP[i+3]);
            $fwrite(fd, "%c", out_BMP[i+4]);
            $fwrite(fd, "%c", out_BMP[i+5]);
        end  
        
        $fclose(fd);
        // To prevent writing more than once, you could clear Write_Done here if needed.
    end
end

// Optional debug displays: show message and first few pixels once writing is done.
always @(posedge HCLK) begin
    if (Write_Done) begin
        $display("Writing BMP file...");
        for (i = 0; i < 10; i = i + 3) begin
            $display("Pixel %0d: R=%d, G=%d, B=%d", i/3, out_BMP[i+2], out_BMP[i+1], out_BMP[i]);
        end
    end
end

endmodule
