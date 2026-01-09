# File City - Comprehensive Feature Documentation

This document catalogs all existing features in File City to ensure nothing breaks during refactoring.

## Overview

File City is a macOS application that visualizes file system directories as 3D cities using Metal-accelerated graphics. Each file/folder becomes a building, with visual properties determined by file metadata.

---

## 1. Core File System Features

### 1.1 Directory Scanning
- **Recursive scanning** with configurable max depth (default: 2)
- **Node count limiting** (max 300 nodes by default)
- **File metadata extraction**: name, size, type, modification date
- **Git repository detection** (checks for `.git` folder)
- **Symlink support** (distinct visual representation)
- **Hidden file filtering** (respects macOS hidden attribute)

### 1.2 File Operations
- **Create folder** - Modal dialog prompts for name
- **Create file** - Modal dialog prompts for name
- **Rename** - Works on selected file/folder
- **Move** - NSOpenPanel to select destination
- **Trash** - Confirmation dialog, uses macOS trash
- **Open** - Opens files with default app
- **Reveal in Finder** - Shows file in Finder window

### 1.3 Navigation
- **Root directory navigation** - Browse to any folder
- **Parent directory** - Go up one level
- **Double-click to enter** - Directories become new root
- **URL opening** - Supports dragging directories onto app icon
- **Launch arguments** - `--root /path` to open specific directory
- **Environment variable** - `FILE_CITY_ROOT` sets default directory
- **Default fallback** - Opens `~/projects` if no root specified

### 1.4 Selection
- **Single selection** - Click in 3D view or list
- **Multi-selection** - Cmd+click to add/remove
- **Selection sync** - 3D view and list view stay in sync
- **URL-based selection** - Selection persists across rescans

---

## 2. 3D Visualization Features

### 2.1 City Mapping (CityMapper)
- **Grid layout** - Buildings arranged in square grid
- **Road spacing** - Gaps between buildings for "roads"
- **Size-based sorting** - Larger folders placed first
- **Depth-based sorting** - Shallower paths prioritized
- **Type-based sorting** - Folders before files before symlinks

### 2.2 Building Shapes (7 types)
| ShapeID | Name | Description |
|---------|------|-------------|
| 0 | Standard | Simple cube/box |
| 1 | Taper | Narrows at top (spire) |
| 2 | Pyramid | Comes to a point |
| 3 | SlantX | Wedge slanted on X axis |
| 4 | SlantZ | Wedge slanted on Z axis |
| 5 | Cylinder | Round building |
| 6 | Plane | Aircraft shape (wings) |

### 2.3 Skyscraper Stacking
- **Multi-tier buildings** for large folders
- **Tier count** based on height (2-4 tiers)
- **Base → Mid → Upper → Crown** sections
- **Footprint shrinking** as tiers go up
- **Crown shapes** vary (taper, pyramid, slant)

### 2.4 Building Properties
- **Height** - Log scale based on folder size
- **Footprint** - Larger for folders than files
- **Material ID** - Hash-based for variety
- **Texture Index** - Semantic mapping (0-31 indexes)
- **Rotation** - Wedges rotate based on camera yaw

### 2.5 Texture Mapping
| Index | Semantic Meaning |
|-------|-----------------|
| 0 | File City |
| 1 | AppShell |
| 2 | Core |
| 3-13 | Various project types |
| 14 | Swift files |
| 15 | Code files (JSON, JS, etc.) |
| 16 | Text/documents |
| 17 | Images |
| 18 | Audio |
| 19 | Video |
| 20 | Archives |
| 21 | Databases |
| 22-31 | Random styles |
| 32 | Road texture |
| 33 | Car texture |
| 34 | Plane texture |
| 35 | Font atlas |

---

## 3. Git Integration

### 3.1 Repository Detection
- **Auto-detect git repos** - Folders with `.git` subdirectory
- **Beacon towers** - Visual indicators on git repo buildings
- **Clean/dirty status** - Green beacon = clean, red = dirty

### 3.2 Git Status Display
- **Hover over beacon** - Shows branch and status
- **Status formatting** - Untracked, Modified, Staged, etc.
- **Async status check** - Background refresh of git status

### 3.3 Time Travel (Git History)
- **Commit history loading** - Up to 200 commits
- **Timeline slider** - Scrub through history (0=oldest, 1=live)
- **Historical tree loading** - `git ls-tree` for past states
- **Tree caching** - Cached historical states for smooth scrubbing
- **Live preview** - Updates city while dragging slider
- **"Now" button** - Return to live mode

---

## 4. File Activity Monitoring

### 4.1 FSEvents Watcher
- **Real-time file change detection**
- **Debounced rescanning** (250ms delay)
- **Write detection** (limited without root)

### 4.2 Privileged Helper (Root Access)
- **SMJobBless installation** - Standard macOS privilege escalation
- **fs_usage monitoring** - Full read/write tracking
- **Unix socket communication** - `/tmp/filecity-activity.sock`
- **Process filtering** - Tracks LLM tools (claude, codex, gemini, cursor, etc.)
- **Event throttling** - 150ms dedup window

### 4.3 Activity Visualization
- **Helicopters on write** - Fly to target building
- **Beams on read** - Vertical light effect
- **Info panel** - Shows process name and file path
- **Glow effect** - Buildings glow during activity
- **Duration** - 1.4 second activity pulse

---

## 5. User Interface

### 5.1 Layout (3-panel)
- **Left sidebar** - Favorites from Finder
- **Middle panel** - File list view (NSTableView)
- **Right panel** - 3D Metal view

### 5.2 File List View (FinderListView)
- **Sortable columns** - Name, Date, Size, Kind
- **Multi-selection** - Shift/Cmd+click
- **Drag and drop** - Reorder, move to folders
- **Context menu** - Open, Rename, Trash, Copy, Reveal
- **Keyboard shortcuts**:
  - Enter - Rename
  - Cmd+Delete - Trash
  - Cmd+C - Copy
  - Cmd+V - Paste

### 5.3 Favorites Sidebar
- **Reads macOS Finder favorites**
- **SF Symbol icons**
- **Click to navigate**

### 5.4 Info Panels
- **Hover info** - Name, kind, size, date, path
- **Git status** - Branch, changes
- **Activity info** - Process, operation, file

### 5.5 Search
- **Cmd+F** to focus search field
- **Fuzzy matching** - Searches file names
- **Debounced** (150ms)
- **Results filter list view**

---

## 6. Camera & Navigation

### 6.1 Isometric Mode (Default)
- **Fixed pitch/yaw** - Classic isometric view
- **Scroll to zoom** - Distance-based
- **Two-finger pan** - Move camera target
- **Pinch to zoom** - Magnification gesture
- **Auto-fit** - Centers on city when loading

### 6.2 First-Person Mode
- **Toggle with F key**
- **WASD movement** - Standard FPS controls
- **Mouse look** - Rotate camera (when captured)
- **Click to capture mouse**
- **ESC to release/exit**

### 6.3 Movement Options
- **Gravity mode** - Falls, can jump (Space)
- **Flying mode** - Double-tap Space to toggle
- **Sprint** - Double-tap W
- **Collision detection** - Can't walk through buildings
- **Rooftop landing** - Land on building tops

### 6.4 Grapple System
- **Hold Shift** - Grapple to target
- **Targets**: Buildings, planes, helicopters, cars, beacons
- **Pull toward target** - Fast movement
- **Attach and ride** - Stay connected to moving objects

---

## 7. Vehicles & Dynamic Objects

### 7.1 Cars
- **Auto-generated paths** - Drive on roads
- **Multiple colors** (12 palette)
- **Multi-part model** - Body, glass, wheels, lights
- **Tesla Model 3 shape** - Custom vertex deformation

### 7.2 Planes
- **Flight paths** - Generated from road grid
- **Hover to speed up** - Looking at plane increases speed
- **Click to explode** - Debris physics
- **Respawn** - New path after explosion
- **Banner** - Trailing banner with directory name

### 7.3 Helicopters
- **Spawn on file writes** - Fly to target building
- **Activity indicator** - Visual feedback for LLM writes

### 7.4 Beams
- **Spawn on file reads** - Vertical light
- **Activity indicator** - Visual feedback for LLM reads

---

## 8. Plane Piloting

### 8.1 Boarding
- **Grapple to plane** - Get close
- **Press E to board** - Enter cockpit
- **Press E to exit** - Return to first-person

### 8.2 Flight Controls
- **W/S** - Pitch (nose down/up)
- **A/D** - Roll (bank left/right)
- **Space** - Boost
- **Mouse** - Camera look offset

### 8.3 Flight Physics
- **Thrust/lift/drag/gravity** - Realistic model
- **Banking turns** - Roll affects yaw
- **Stall prevention** - Minimum speed maintained
- **Auto-leveling** - Roll/pitch return to level
- **Minimum altitude** - Can't crash into ground

---

## 9. Rendering Features

### 9.1 Metal Pipeline
- **Instanced rendering** - Efficient GPU rendering
- **Depth testing** - Proper occlusion
- **Alpha blending** - Transparency support
- **Texture arrays** - 36 texture slots
- **Custom samplers** - Linear filtering, repeat mode

### 9.2 Visual Effects
- **Selection highlight** - Yellow tint
- **Hover highlight** - Brightness boost
- **Activity glow** - Orange (write) / Blue (read)
- **Git beacon shapes** - Different for clean/dirty
- **Waving banner** - Animated text

### 9.3 Procedural Generation
- **Building textures** - Generated from seed strings
- **Font atlas** - Generated for text rendering
- **Deterministic** - Same path = same appearance

---

## 10. Ray Picking

### 10.1 Block Picking
- **Ray-box intersection** - Hit detection
- **Shape-aware** - Different bounds for pyramid, wedge, etc.
- **Distance sorting** - Returns closest hit

### 10.2 Beacon Picking
- **Inflated bounds** - Easier to click
- **Separate pass** - After block picking

### 10.3 Plane/Helicopter Picking
- **Click to interact** - Explode planes
- **Hover detection** - Speed up planes

---

## 11. Data Models

### 11.1 FileNode
```swift
struct FileNode {
    id: UUID
    url: URL
    name: String
    type: NodeType (.file, .folder, .symlink)
    sizeBytes: Int64
    modifiedAt: Date
    children: [FileNode]
    isHidden: Bool
    isGitRepo: Bool
    isGitClean: Bool
}
```

### 11.2 CityBlock
```swift
struct CityBlock {
    id: UUID
    nodeID: UUID
    name: String
    position: SIMD3<Float>
    footprint: SIMD2<Int32>
    height: Int32
    materialID: Int32
    textureIndex: Int32
    shapeID: Int32
    isPinned: Bool
    isGitRepo: Bool
    isGitClean: Bool
}
```

### 11.3 GitCommit
```swift
struct GitCommit {
    id: String (full hash)
    shortHash: String (7 chars)
    timestamp: Date
    subject: String
}
```

---

## 12. Existing Tests

### 12.1 RayTracerTests
- `testIntersectStandardBlock` - Basic hit detection
- `testMissStandardBlock` - Miss above block
- `testIntersectRaisedBlock` - Hit elevated block
- `testIntersectPyramidTip` - Hit pyramid shape
- `testMissPyramidEmptySpace` - Miss around pyramid
- `testIntersectTaperedBlock` - Hit tapered shape
- `testIntersectCylinderBlock` - Hit cylinder shape

### 12.2 BeaconPickerTests
- Git beacon ray-picking logic tests

### 12.3 File_CityTests
- Basic sanity tests

---

## 13. Build & Configuration

### 13.1 Makefile Targets
- `make build` - Build debug
- `make install` - Install to /Applications
- `make run` - Build and launch
- `make test` - Run unit tests
- `make clean` - Clean build artifacts

### 13.2 Project Structure
```
File City/
├── File City.xcodeproj
├── File City/
│   ├── AppShell/        # UI layer
│   ├── Core/            # Business logic
│   │   ├── Models/
│   │   ├── Scanner/
│   │   ├── Mapper/
│   │   ├── Renderer/
│   │   ├── Watcher/
│   │   ├── Physics/
│   │   ├── Search/
│   │   ├── Actions/
│   │   └── Services/
│   └── Resources/
│       ├── Shaders/
│       └── Textures/
├── File CityTests/
├── File CityUITests/
└── Helper/              # Privileged daemon
```

---

## Feature Verification Checklist

Use this checklist to verify features after refactoring:

### Navigation
- [ ] Open directory via menu/dialog
- [ ] Navigate to parent
- [ ] Double-click to enter folder
- [ ] Drag directory onto app icon
- [ ] Launch with --root argument

### File Operations
- [ ] Create folder
- [ ] Create file
- [ ] Rename
- [ ] Move
- [ ] Trash
- [ ] Open file
- [ ] Reveal in Finder

### Selection
- [ ] Single click to select
- [ ] Cmd+click for multi-select
- [ ] Selection syncs between views

### 3D View
- [ ] Buildings render correctly
- [ ] All shape types display properly
- [ ] Hover highlights work
- [ ] Selection highlights work
- [ ] Zoom works
- [ ] Pan works

### First-Person Mode
- [ ] F toggles mode
- [ ] WASD movement
- [ ] Mouse look
- [ ] Collision detection
- [ ] Jump/fly toggle
- [ ] Sprint
- [ ] Grapple

### Git Features
- [ ] Repos detected
- [ ] Beacon towers appear
- [ ] Clean/dirty status
- [ ] Time travel slider
- [ ] Historical tree loading

### Activity Monitoring
- [ ] Helicopters spawn on write
- [ ] Beams spawn on read
- [ ] Info panel shows activity

### Vehicles
- [ ] Cars drive on roads
- [ ] Planes fly
- [ ] Click to explode plane
- [ ] Board/exit plane
- [ ] Flight controls work

### Search
- [ ] Cmd+F focuses search
- [ ] Typing filters list
- [ ] Results update in real-time

### File List
- [ ] Columns sort correctly
- [ ] Context menu works
- [ ] Keyboard shortcuts work
- [ ] Drag and drop works
