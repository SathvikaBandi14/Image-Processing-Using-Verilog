`timescale 1ns / 1ps
/******************************************************************************/
/******************  Module for reading and processing image     **************/
/******************************************************************************/
`include "definitions.v"  // Include definition file

module image_processor
#(
    parameter IMAGE_WIDTH  = 384,  // Image width
    parameter IMAGE_HEIGHT = 256,  // Image height
    parameter INPUT_FILE   = "C:/Users/Tingu/image_processing_project_5/image_processing_project_5.srcs/sources_1/new/parrots.hex",  // Input image file
    parameter STARTUP_DELAY = 100,  // Delay during startup
    parameter HSYNC_DELAY  = 160,   // Delay between HSYNC pulses
    parameter BRIGHTNESS_VALUE = 100,  // Brightness adjustment value
    parameter THRESHOLD_VALUE = 90,    // Threshold value for threshold operation
    parameter BRIGHTNESS_SIGN = 0 ,    // Brightness operation sign (0: subtraction, 1: addition)
    parameter signed SATURATION_FACTOR = 2
)
(
    input clock,                // Clock input
    input reset_n,              // Active-low reset
    output vsync,               // Vertical sync pulse
    output reg hsync,           // Horizontal sync pulse
    output reg [7:0] red_even,  // Red component for even pixel
    output reg [7:0] green_even,// Green component for even pixel
    output reg [7:0] blue_even, // Blue component for even pixel
    output reg [7:0] red_odd,   // Red component for odd pixel
    output reg [7:0] green_odd, // Green component for odd pixel
    output reg [7:0] blue_odd,  // Blue component for odd pixel
    output processing_done      // Done flag
);

//-------------------------------------------------
// Internal Signals
//-------------------------------------------------
parameter PIXEL_WIDTH = 8;  // Bit width of each color component
parameter IMAGE_SIZE  = IMAGE_WIDTH * IMAGE_HEIGHT * 3;  // Total image size in bytes

// FSM states
localparam STATE_IDLE  = 2'b00;  // Idle state
localparam STATE_VSYNC = 2'b01;  // VSYNC state
localparam STATE_HSYNC = 2'b10;  // HSYNC state
localparam STATE_DATA  = 2'b11;  // Data processing state

reg [1:0] current_state, next_state;  // FSM states
reg start_signal;                     // Start signal for FSM
reg reset_delayed;                    // Delayed reset signal
reg vsync_counter_enable;             // Enable signal for VSYNC counter
reg [8:0] vsync_counter;              // VSYNC counter
reg hsync_counter_enable;             // Enable signal for HSYNC counter
reg [8:0] hsync_counter;              // HSYNC counter
reg data_processing_enable;           // Enable signal for data processing

// Image data storage
reg [7:0] image_memory [0:IMAGE_SIZE-1];  // Memory to store 8-bit image data
integer temp_image [0:IMAGE_WIDTH*IMAGE_HEIGHT*3-1];  // Temporary image storage
integer red_data [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];      // Red component storage
integer green_data [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];    // Green component storage
integer blue_data [0:IMAGE_WIDTH*IMAGE_HEIGHT-1];     // Blue component storage

// Temporary variables for calculations
integer temp_red_even, temp_red_odd, temp_green_even, temp_green_odd, temp_blue_even, temp_blue_odd;
integer temp_value, temp_value1, temp_value2, temp_value4;
integer stemp_red_even, stemp_red_odd, stemp_green_even, stemp_green_odd, stemp_blue_even, stemp_blue_odd;
 // Internal signals for pixel0
reg [PIXEL_WIDTH-1:0] Y0;             // Luminance for pixel0
reg signed [PIXEL_WIDTH:0] R0_diff, G0_diff, B0_diff; // Differences for pixel0
reg signed [PIXEL_WIDTH+3:0] R0_sat, G0_sat, B0_sat;    // Saturated channels (wider to handle multiplication)

// Internal signals for pixel1
reg [PIXEL_WIDTH-1:0] Y1;             // Luminance for pixel1
reg signed [PIXEL_WIDTH:0] R1_diff, G1_diff, B1_diff; // Differences for pixel1
reg signed [PIXEL_WIDTH+3:0] R1_sat, G1_sat, B1_sat;    // Saturated channels (wider to handle multiplication)

// Row and column indices
reg [8:0] current_row;  // Current row index
reg [8:0] current_col;  // Current column index
reg [18:0] pixel_count; // Pixel counter

//-------------------------------------------------//
// -------- Reading data from input file ----------//
//-------------------------------------------------//
initial begin
    $readmemh(INPUT_FILE, image_memory, 0, IMAGE_SIZE-1);  // Read image data from file
end

// Transfer data from image_memory to temporary storage
always @(start_signal) begin
    if (start_signal == 1'b1) begin
        for (integer i = 0; i < IMAGE_WIDTH * IMAGE_HEIGHT * 3; i = i + 1) begin
            temp_image[i] = image_memory[i][7:0];  // Store 8-bit data in temporary storage
        end

        // Flip the image vertically (bottom-to-top)
        for (integer i = 0; i < IMAGE_HEIGHT; i = i + 1) begin
            for (integer j = 0; j < IMAGE_WIDTH; j = j + 1) begin
                red_data[IMAGE_WIDTH * i + j]   = temp_image[IMAGE_WIDTH * 3 * (IMAGE_HEIGHT - i - 1) + 3 * j + 0];  // Red
                green_data[IMAGE_WIDTH * i + j] = temp_image[IMAGE_WIDTH * 3 * (IMAGE_HEIGHT - i - 1) + 3 * j + 1];  // Green
                blue_data[IMAGE_WIDTH * i + j]  = temp_image[IMAGE_WIDTH * 3 * (IMAGE_HEIGHT - i - 1) + 3 * j + 2];  // Blue
            end
        end
    end
end

//----------------------------------------------------//
// ---Begin to read image file once reset is high ---//
//----------------------------------------------------//
always @(posedge clock, negedge reset_n) begin
    if (!reset_n) begin
        start_signal <= 0;
        reset_delayed <= 0;
    end else begin
        reset_delayed <= reset_n;
        if (reset_n == 1'b1 && reset_delayed == 1'b0) begin
            start_signal <= 1'b1;  // Generate start pulse
        end else begin
            start_signal <= 1'b0;
        end
    end
end

//-----------------------------------------------------------------------------------------------//
// Finite state machine for reading RGB888 data and generating VSYNC and HSYNC pulses             //
//-----------------------------------------------------------------------------------------------//
always @(posedge clock, negedge reset_n) begin
    if (!reset_n) begin
        current_state <= STATE_IDLE;
    end else begin
        current_state <= next_state;
    end
end

// State transition logic
always @(*) begin
    case (current_state)
        STATE_IDLE: begin
            if (start_signal) next_state = STATE_VSYNC;
            else next_state = STATE_IDLE;
        end
        STATE_VSYNC: begin
            if (vsync_counter == STARTUP_DELAY) next_state = STATE_HSYNC;
            else next_state = STATE_VSYNC;
        end
        STATE_HSYNC: begin
            if (hsync_counter == HSYNC_DELAY) next_state = STATE_DATA;
            else next_state = STATE_HSYNC;
        end
        STATE_DATA: begin
            if (processing_done) next_state = STATE_IDLE;
            else begin
                if (current_col == IMAGE_WIDTH - 2) next_state = STATE_HSYNC;
                else next_state = STATE_DATA;
            end
        end
    endcase
end

// Counter control logic
always @(*) begin
    vsync_counter_enable = 0;
    hsync_counter_enable = 0;
    data_processing_enable = 0;
    case (current_state)
        STATE_VSYNC: vsync_counter_enable = 1;
        STATE_HSYNC: hsync_counter_enable = 1;
        STATE_DATA:  data_processing_enable = 1;
    endcase
end

// VSYNC and HSYNC counters
always @(posedge clock, negedge reset_n) begin
    if (!reset_n) begin
        vsync_counter <= 0;
        hsync_counter <= 0;
    end else begin
        if (vsync_counter_enable) vsync_counter <= vsync_counter + 1;
        else vsync_counter <= 0;

        if (hsync_counter_enable) hsync_counter <= hsync_counter + 1;
        else hsync_counter <= 0;
    end
end

// Row and column counters
always @(posedge clock, negedge reset_n) begin
    if (!reset_n) begin
        current_row <= 0;
        current_col <= 0;
    end else begin
        if (data_processing_enable) begin
            if (current_col == IMAGE_WIDTH - 2) begin
                current_row <= current_row + 1;
            end
            if (current_col == IMAGE_WIDTH - 2) current_col <= 0;
            else current_col <= current_col + 2;  // Process two pixels at a time
        end
    end
end

// Pixel counter
always @(posedge clock, negedge reset_n) begin
    if (!reset_n) begin
        pixel_count <= 0;
    end else begin
        if (data_processing_enable) pixel_count <= pixel_count + 1;
    end
end

assign vsync = vsync_counter_enable;
assign processing_done = (pixel_count == IMAGE_WIDTH * IMAGE_HEIGHT / 2 - 1) ? 1'b1 : 1'b0;

// Image processing logic
always @(*) begin
    hsync = 1'b0;
    red_even = 0;
    green_even = 0;
    blue_even = 0;
    red_odd = 0;
    green_odd = 0;
    blue_odd = 0;

    if (data_processing_enable) begin
        hsync = 1'b1;

        // Brightness operation
        `ifdef BRIGHTNESS_OPERATION
        if (BRIGHTNESS_SIGN == 1) begin
            // Brightness addition
            temp_red_even   = red_data[IMAGE_WIDTH * current_row + current_col] + BRIGHTNESS_VALUE;
            temp_red_odd    = red_data[IMAGE_WIDTH * current_row + current_col + 1] + BRIGHTNESS_VALUE;
            temp_green_even = green_data[IMAGE_WIDTH * current_row + current_col] + BRIGHTNESS_VALUE;
            temp_green_odd  = green_data[IMAGE_WIDTH * current_row + current_col + 1] + BRIGHTNESS_VALUE;
            temp_blue_even  = blue_data[IMAGE_WIDTH * current_row + current_col] + BRIGHTNESS_VALUE;
            temp_blue_odd   = blue_data[IMAGE_WIDTH * current_row + current_col + 1] + BRIGHTNESS_VALUE;

            // Clamp values to 0-255
            red_even   = (temp_red_even > 255) ? 255 : temp_red_even;
            red_odd    = (temp_red_odd > 255) ? 255 : temp_red_odd;
            green_even = (temp_green_even > 255) ? 255 : temp_green_even;
            green_odd  = (temp_green_odd > 255) ? 255 : temp_green_odd;
            blue_even  = (temp_blue_even > 255) ? 255 : temp_blue_even;
            blue_odd   = (temp_blue_odd > 255) ? 255 : temp_blue_odd;
        end else begin
            // Brightness subtraction
            temp_red_even   = red_data[IMAGE_WIDTH * current_row + current_col] - BRIGHTNESS_VALUE;
            temp_red_odd    = red_data[IMAGE_WIDTH * current_row + current_col + 1] - BRIGHTNESS_VALUE;
            temp_green_even = green_data[IMAGE_WIDTH * current_row + current_col] - BRIGHTNESS_VALUE;
            temp_green_odd  = green_data[IMAGE_WIDTH * current_row + current_col + 1] - BRIGHTNESS_VALUE;
            temp_blue_even  = blue_data[IMAGE_WIDTH * current_row + current_col] - BRIGHTNESS_VALUE;
            temp_blue_odd   = blue_data[IMAGE_WIDTH * current_row + current_col + 1] - BRIGHTNESS_VALUE;

            // Clamp values to 0-255
            red_even   = (temp_red_even < 0) ? 0 : temp_red_even;
            red_odd    = (temp_red_odd < 0) ? 0 : temp_red_odd;
            green_even = (temp_green_even < 0) ? 0 : temp_green_even;
            green_odd  = (temp_green_odd < 0) ? 0 : temp_green_odd;
            blue_even  = (temp_blue_even < 0) ? 0 : temp_blue_even;
            blue_odd   = (temp_blue_odd < 0) ? 0 : temp_blue_odd;
        end
        `endif

        // Invert operation
        `ifdef INVERT_OPERATION
        temp_value2 = (blue_data[IMAGE_WIDTH * current_row + current_col] + red_data[IMAGE_WIDTH * current_row + current_col] + green_data[IMAGE_WIDTH * current_row + current_col]) / 3;
        red_even   = 255 - temp_value2;
        green_even = 255 - temp_value2;
        blue_even  = 255 - temp_value2;

        temp_value4 = (blue_data[IMAGE_WIDTH * current_row + current_col + 1] + red_data[IMAGE_WIDTH * current_row + current_col + 1] + green_data[IMAGE_WIDTH * current_row + current_col + 1]) / 3;
        red_odd    = 255 - temp_value4;
        green_odd  = 255 - temp_value4;
        blue_odd   = 255 - temp_value4;
        `endif

        // Threshold operation
        `ifdef THRESHOLD_OPERATION
        temp_value = (red_data[IMAGE_WIDTH * current_row + current_col] + green_data[IMAGE_WIDTH * current_row + current_col] + blue_data[IMAGE_WIDTH * current_row + current_col]) / 3;
        if (temp_value > THRESHOLD_VALUE) begin
            red_even = 255;
            green_even = 255;
            blue_even = 255;
        end else begin
            red_even = 0;
            green_even = 0;
            blue_even = 0;
        end

        temp_value1 = (red_data[IMAGE_WIDTH * current_row + current_col + 1] + green_data[IMAGE_WIDTH * current_row + current_col + 1] + blue_data[IMAGE_WIDTH * current_row + current_col + 1]) / 3;
        if (temp_value1 > THRESHOLD_VALUE) begin
            red_odd = 255;
            green_odd = 255;
            blue_odd = 255;
        end else begin
            red_odd = 0;
            green_odd = 0;
            blue_odd = 0;
        end
        `endif
        
        `ifdef SATURATION_OPERATION
    // Pixel 0 calculations:
    // Step 1: Calculate luminance using fixed-point arithmetic
    // Using weights approximating: 0.299, 0.587, 0.114
    stemp_red_even  = red_data[IMAGE_WIDTH * current_row + current_col];
    stemp_green_even = green_data[IMAGE_WIDTH * current_row + current_col]; // Corrected from red_data
    stemp_blue_even = blue_data[IMAGE_WIDTH * current_row + current_col];   // Corrected from red_data
    stemp_red_odd  = red_data[IMAGE_WIDTH * current_row + current_col + 1];
    stemp_green_odd = green_data[IMAGE_WIDTH * current_row + current_col + 1];
    stemp_blue_odd = blue_data[IMAGE_WIDTH * current_row + current_col + 1];

    Y0 = (77 * stemp_red_even + 150 * stemp_green_even + 29 * stemp_blue_even) >> 8;

    // Step 2: Compute differences between channels and luminance
     
    R0_diff = $signed(stemp_red_even) - $signed(Y0);
    G0_diff = $signed(stemp_green_even) - $signed(Y0);
    B0_diff = $signed(stemp_blue_even) - $signed(Y0);

    // Step 3: Apply saturation factor
    R0_sat = $signed(Y0) + (R0_diff * SATURATION_FACTOR);
    G0_sat = $signed(Y0) + (G0_diff * SATURATION_FACTOR);
    B0_sat = $signed(Y0) + (B0_diff * SATURATION_FACTOR);

    // Step 4: Clamp results to the range [0, 255]
    red_even = (R0_sat > 255) ? 8'd255 : (R0_sat < 0) ? 8'd0 : R0_sat[7:0];
    green_even = (G0_sat > 255) ? 8'd255 : (G0_sat < 0) ? 8'd0 : G0_sat[PIXEL_WIDTH-1:0];
    blue_even  = (B0_sat > 255) ? 8'd255 : (B0_sat < 0) ? 8'd0 : B0_sat[PIXEL_WIDTH-1:0];

    // Pixel 1 calculations:
    Y1 = (77 * stemp_red_odd + 150 * stemp_green_odd + 29 * stemp_blue_odd) >> 8;

    R1_diff = $signed(stemp_red_odd) - $signed(Y1);
    G1_diff = $signed(stemp_green_odd) - $signed(Y1);
    B1_diff = $signed(stemp_blue_odd) - $signed(Y1);

    R1_sat = $signed(Y1) + (R1_diff * SATURATION_FACTOR);
    G1_sat = $signed(Y1) + (G1_diff * SATURATION_FACTOR);
    B1_sat = $signed(Y1) + (B1_diff * SATURATION_FACTOR);

    red_odd   = (R1_sat > 255) ? 8'd255 : (R1_sat < 0) ? 8'd0 : R1_sat[PIXEL_WIDTH-1:0];
    green_odd = (G1_sat > 255) ? 8'd255 : (G1_sat < 0) ? 8'd0 : G1_sat[PIXEL_WIDTH-1:0];
    blue_odd  = (B1_sat > 255) ? 8'd255 : (B1_sat < 0) ? 8'd0 : B1_sat[PIXEL_WIDTH-1:0];

`endif


    end
end

endmodule