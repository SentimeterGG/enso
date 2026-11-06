shader_type canvas_item;
render_mode unshaded; // Removes all engine shadows, lighting, and gradients

// Controls the block size of your pixels. 
// Match this value to the thickness scale of your menu text.
uniform float pixel_scale : hint_range(1.0, 16.0, 1.0) = 4.0;

void vertex() {
    // 1. Grab the high-res 1080p vertex positions
    // 2. Divide by the scale and use floor() to snap them to a strict, integer pixel grid
    // 3. Multiply back to scale it cleanly to the 1080p display
    VERTEX = floor(VERTEX / pixel_scale) * pixel_scale;
}

void fragment() {
    // Outputs the line's raw solid color with zero filtering, blur, or sub-pixel blending
    COLOR = COLOR;
}
