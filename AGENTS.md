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

- **Async Updates Causing Graphics Flashing:**
  - **Root Cause #1 - UUID Regeneration on Rescan:**
    - **Problem:** `FSEventsWatcher` triggers `rescanSubject` which rebuilds all `FileNode` objects with **NEW UUIDs**. Any data stored by UUID (e.g., `locByNodeID: [UUID: Int]`) becomes orphaned because the old UUIDs no longer exist.
    - **Example:** LOC flags were stored in `locByNodeID`. After an FSEvents rescan, all FileNodes got new UUIDs, so the LOC data was never found and flags disappeared.
    - **Solution (Path-based Keying):**
      - Store data by **file path** instead of UUID: `locByPath: [String: Int]`
      - Use a **computed property** to convert to UUID-based for rendering:
        ```swift
        var locByNodeID: [UUID: Int] {
            var result: [UUID: Int] = [:]
            for (path, loc) in locByPath {
                let url = URL(fileURLWithPath: path)
                if let node = nodeByURL[url] { result[node.id] = loc }
            }
            return result
        }
        ```
      - This pattern is already used by `gitCleanByPath` for the same reason.
    - **Applies to:** Any data that must persist across directory rescans (git status, LOC counts, custom annotations, etc.)

  - **Root Cause #2 - Property Update Order:**
    - **Problem:** When `blocks` is assigned, the `$blocks` Combine subscription fires immediately. If computed properties (like `locByNodeID`) depend on other properties (like `nodeByURL`), those must be updated BEFORE `blocks`.
    - **Example:** In `scanRoot()`, `blocks` was assigned before `nodeByURL`. The `$blocks` subscription called `updateFromAppState()`, which computed `locByNodeID` using the OLD `nodeByURL`, returning an empty dictionary.
    - **Solution:** Update dependency properties BEFORE the property that triggers subscriptions:
      ```swift
      // WRONG order - blocks triggers subscription before nodeByURL is ready
      blocks = mapper.map(...)
      nodeByID = buildNodeIDMap(...)
      nodeByURL = buildNodeURLMap(...)

      // CORRECT order - dependencies updated first
      nodeByID = buildNodeIDMap(...)
      nodeByURL = buildNodeURLMap(...)
      blocks = mapper.map(...)
      ```
    - **Applies to:** Any code path that updates multiple related properties where one triggers Combine subscriptions.

  - **Root Cause #3 - Missing Combine Subscription:**
    - **Problem:** When a new `@Published` property is added to AppState (like `locByPath`), the Coordinator in MetalCityView must subscribe to it for re-renders to occur. Without a subscription, the data updates but the renderer never gets notified.
    - **Symptom:** Object appears/disappears but comes back when hovering or interacting (because those actions trigger other subscribed updates).
    - **Solution:** Add subscription in `Coordinator.startObserving()`:
      ```swift
      appState.$locByPath
          .receive(on: DispatchQueue.main)
          .sink { [weak self] _ in
              self?.updateFromAppState()
          }
          .store(in: &cancellables)
      ```
    - **Applies to:** Any new `@Published` property that affects rendering.

  - **Root Cause #4 - Clearing Data Before Rebuild:**
    - **Problem:** When async operations trigger texture/instance rebuilds, clearing data before building new data causes objects to flash/disappear momentarily if a render occurs mid-rebuild.
    - **Solution (Atomic Swap Pattern):**
      1. Build all new data into **temporary local variables** first
      2. Only clear/swap the instance variables **after** new data is fully ready
      3. Swap both the index map and texture array together to maintain consistency
    - **Code Pattern:**
      ```swift
      // BAD - causes flashing:
      textureArray = nil
      indexMap.removeAll()
      // ... build new data ...
      textureArray = newArray

      // GOOD - atomic swap:
      var newIndexMap: [UUID: Int] = [:]
      var newTextures: [MTLTexture] = []
      // ... build into temporaries ...
      // Swap atomically at the end:
      indexMap = newIndexMap
      textureArray = newArrayTexture
      ```
    - **Applies to:** Texture arrays, instance buffers, any data used during render that gets rebuilt from async updates.
