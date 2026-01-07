# Common mistakes
- When calculating fly-over heights for vehicles (like helicopters) in File City, always account for: 1) Shape-specific height boosts (Wedges use 0.75 * height due to 1.5 slope factor, Pyramids use 0.5 * height). 2) Stacked/Compound buildings: scan all blocks at the target (x, z) coordinates to find the global maximum visual height of the entire structure to prevent collisions with upper layers.
- **Building Shape Positioning (Beacons/Beams):**
  - **Wedges (Shape 3 & 4):** The "top" is not the center. The high point is offset to one side.
    - *Logic:* Calculate `beaconOffset` based on `footprint * 0.45`. Apply the block's `rotationY` to this offset vector to find the correct world-space X/Z coordinate for the high point.
  - **Spires (Shape 1 & 2):** The top is the peak center. Visual height is usually `y + height * 1.5` (or specific shader logic).
  - **Stacked Buildings:** When placing an effect "on top" of a file/folder (which might be a lower block in a stack), always search for the **top-most block** at that (X, Z) location. Use the geometry of that *top* block to determine the Y position and X/Z offset.

- **Double-sided Text Rendering (Banners/Signs):**
  - **Mistake:** Assuming `1.0 - uv.x` on the back face is enough. While it fixes letter mirroring, it **scrambles the word order** for multi-segment objects (like the 8-segment banner).
  - **Solution (Correct Logic):**
    1. **Face Detection:** Pass `in.normal` from vertex to fragment shader as `localNormal [[flat]]`. Check `localNormal.z > 0` to identify Front vs. Back face independent of rotation.
    2. **Segment Mapping:**
       - **Front Face:** `globalU = uOffset + (1.0 - in.uv.x) * uWidth`. (Standard L->R)
       - **Back Face:** `globalU = (1.0 - (uOffset + uWidth)) + (1.0 - in.uv.x) * uWidth`.
    3. **Why?** On the back face, the segments appear in reverse order (End->Start). You must "move" the texture window to the opposite side of the atlas (`1.0 - (Start + Width)`) to maintain the visual word progression (Start of word on the left).
