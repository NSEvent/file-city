# Common mistakes
- When calculating fly-over heights for vehicles (like helicopters) in File City, always account for: 1) Shape-specific height boosts (Wedges use 0.75 * height due to 1.5 slope factor, Pyramids use 0.5 * height). 2) Stacked/Compound buildings: scan all blocks at the target (x, z) coordinates to find the global maximum visual height of the entire structure to prevent collisions with upper layers.
- **Building Shape Positioning (Beacons/Beams):**
  - **Wedges (Shape 3 & 4):** The "top" is not the center. The high point is offset to one side.
    - *Logic:* Calculate `beaconOffset` based on `footprint * 0.45`. Apply the block's `rotationY` to this offset vector to find the correct world-space X/Z coordinate for the high point.
  - **Spires (Shape 1 & 2):** The top is the peak center. Visual height is usually `y + height * 1.5` (or specific shader logic).
  - **Stacked Buildings:** When placing an effect "on top" of a file/folder (which might be a lower block in a stack), always search for the **top-most block** at that (X, Z) location. Use the geometry of that *top* block to determine the Y position and X/Z offset.