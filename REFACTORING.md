# File City - Refactoring Plan

This document outlines identified issues and planned refactoring/optimization work.

---

## 1. Code Quality Issues Identified

### 1.1 AppState.swift (1078 lines) - GOD CLASS
**Problem:** AppState handles too many responsibilities:
- File scanning
- Git operations
- Time travel logic
- Activity monitoring
- Selection management
- File operations
- Search indexing
- Watchers management

**Solution:** Extract into focused service classes:
- `GitService` - Git status, commit history, dirty detection
- `TimeTravelManager` - Historical tree loading, caching, mode switching
- `ActivityMonitor` - File activity tracking, helicopter/beam triggers

### 1.2 Magic Numbers
**Problem:** Hard-coded values scattered throughout:
- `maxNodes = 300`
- `maxDepth = 2`
- `throttleInterval = 0.15`
- Various animation durations
- Heights, widths, speeds

**Solution:** Create `Constants.swift` with organized constants:
```swift
enum Constants {
    enum Scanning {
        static let maxNodes = 300
        static let maxDepth = 2
    }
    enum Animation {
        static let activityDuration: TimeInterval = 1.4
        static let throttleInterval: TimeInterval = 0.15
    }
    // etc.
}
```

### 1.3 CityMapper Complexity
**Problem:**
- Long functions with complex nesting
- Repeated tier-building logic
- Hard-coded building shape parameters

**Solution:**
- Extract `BuildingStyler` for shape/texture selection
- Extract tier-building into reusable function
- Move constants to `LayoutRules.swift`

### 1.4 Duplicate Code Patterns
**Problem:**
- `visualTopY(for:)` appears in multiple places (MetalRenderer, elsewhere)
- `rotationYForWedge()` duplicated in RayTracer and MetalRenderer
- Similar loop patterns for finding max height at X/Z location

**Solution:**
- Move shared geometry helpers to `GeometryHelpers.swift`
- Create extension on `CityBlock` for computed properties

### 1.5 MetalRenderer Size (1600+ lines)
**Problem:** MetalRenderer is too large, handling:
- Pipeline setup
- Building rendering
- Car paths and instances
- Plane paths and instances
- Explosions
- Helicopters
- Beams
- Signposts
- Picking

**Solution:** Extract managers:
- `VehiclePathManager` - Car/plane path generation
- `ExplosionManager` - Explosion particle state
- Keep core rendering in MetalRenderer

---

## 2. Performance Optimizations

### 2.1 Instance Buffer Rebuilding
**Issue:** `rebuildInstancesUsingCache()` called frequently
**Fix:** Only rebuild when blocks actually change, use dirty flags

### 2.2 Block Height Lookups
**Issue:** O(n) search for blocks at same X/Z repeated many times
**Fix:** Create spatial index (dictionary by grid position)

### 2.3 Git Status Polling
**Issue:** Status checked for all repos on every rescan
**Fix:** Cache status with TTL, only refresh on FSEvents trigger

### 2.4 Texture Array Creation
**Issue:** Full rebuild on every block set change
**Fix:** Incremental updates when possible

---

## 3. Specific Refactoring Tasks

### Task 1: Extract GitService
```swift
// New file: Core/Services/GitService.swift
final class GitService {
    func isGitRepository(at url: URL) -> Bool
    func getStatus(at url: URL) async -> GitStatus
    func getCommitHistory(at url: URL, limit: Int) async -> [GitCommit]
    func getTreeAtCommit(_ commit: GitCommit, in url: URL) async -> FileNode?
}
```

### Task 2: Extract TimeTravelManager
```swift
// New file: Core/Services/TimeTravelManager.swift
@MainActor
final class TimeTravelManager: ObservableObject {
    @Published var mode: TimeTravelMode = .live
    @Published var commitHistory: [GitCommit] = []
    private var historicalTreeCache: [String: FileNode] = [:]

    func loadHistory(for url: URL) async
    func loadTreeForCommit(_ commit: GitCommit) async -> FileNode?
    func clearCache()
}
```

### Task 3: Create Constants.swift
```swift
// New file: Core/Constants.swift
enum Constants {
    enum Scanning { ... }
    enum Layout { ... }
    enum Animation { ... }
    enum Camera { ... }
    enum Vehicles { ... }
}
```

### Task 4: Extract GeometryHelpers
```swift
// New file: Core/Renderer/GeometryHelpers.swift
func visualTopY(for block: CityBlock) -> Float
func rotationYForWedge(block: CityBlock, cameraYaw: Float) -> Float
func maxHeightAt(x: Float, z: Float, in blocks: [CityBlock]) -> Float
```

### Task 5: CityBlock Extensions
```swift
// Extension in CityBlock.swift
extension CityBlock {
    var visualTop: Float { ... }
    var gridKey: GridKey { ... }
}

struct GridKey: Hashable {
    let x: Int
    let z: Int
}
```

---

## 4. Testing Strategy

### Before Refactoring
1. Ensure existing tests pass
2. Add integration tests for key workflows:
   - Directory scanning produces expected blocks
   - CityMapper layout is deterministic
   - Selection sync works
   - Git detection works

### After Each Refactoring Step
1. Run all tests
2. Manual verification:
   - App launches
   - Can navigate directories
   - 3D view renders
   - Selection works
   - Git features work

---

## 5. Implementation Order

1. ✅ Document features (FEATURES.md)
2. ✅ Document refactoring plan (this file)
3. Add pre-refactoring tests
4. Create Constants.swift (safe, additive)
5. Extract GeometryHelpers (safe, no behavior change)
6. Extract GitService (moderate risk)
7. Extract TimeTravelManager (moderate risk)
8. Simplify AppState (high impact)
9. Optimize MetalRenderer (moderate risk)
10. Final verification

---

## 6. Files to Create

- [ ] `Core/Constants.swift`
- [ ] `Core/Services/GitService.swift`
- [ ] `Core/Services/TimeTravelManager.swift`
- [ ] `Core/Renderer/GeometryHelpers.swift`
- [ ] Additional unit tests

## 7. Files to Modify

- [ ] `AppState.swift` - Remove extracted code, use new services
- [ ] `CityMapper.swift` - Use constants, simplify
- [ ] `MetalRenderer.swift` - Use GeometryHelpers
- [ ] `RayTracer.swift` - Use shared helpers
- [ ] `CityBlock.swift` - Add extensions
