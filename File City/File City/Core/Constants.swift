import Foundation
import simd

/// Centralized constants for File City
/// Organized by feature area to make finding and updating values easy
enum Constants {

    // MARK: - Scanning

    enum Scanning {
        /// Maximum depth to recursively scan directories
        static let maxDepth = 2

        /// Maximum number of file nodes to scan
        static let maxNodes = 300

        /// Interval to throttle FSEvents file activity (seconds)
        static let activityThrottleInterval: TimeInterval = 0.15

        /// Delay before rescanning after file system change (seconds)
        static let rescanDebounceDelay: TimeInterval = 0.25
    }

    // MARK: - Layout (City Grid)

    enum Layout {
        /// Width of roads between buildings (grid units)
        static let roadWidth: Int = 2

        /// Padding around blocks (grid units)
        static let blockPadding: Int = 1

        /// Minimum building footprint size
        static let minBlockSize: Int = 2

        /// Maximum building footprint size
        static let maxBlockSize: Int = 12

        /// Maximum building height
        static let maxBuildingHeight: Int = 64

        /// Distance at which LOD changes apply
        static let lodDistance: Float = 200

        /// Maximum nodes for layout processing
        static let maxLayoutNodes: Int = 20000

        /// Grid spacing between buildings
        static let gridSpacing: Float = 2.0
    }

    // MARK: - Building Shapes

    enum Shapes {
        /// Standard cube building
        static let standard: Int32 = 0

        /// Tapered spire building
        static let taper: Int32 = 1

        /// Pyramid building
        static let pyramid: Int32 = 2

        /// Wedge slanted on X axis
        static let slantX: Int32 = 3

        /// Wedge slanted on Z axis
        static let slantZ: Int32 = 4

        /// Cylindrical building
        static let cylinder: Int32 = 5

        /// Plane shape (for aircraft)
        static let plane: Int32 = 6

        /// Car body shape
        static let car: Int32 = 7

        /// Sign label
        static let signLabel: Int32 = 11

        /// Light beam (anchored at bottom)
        static let beam: Int32 = 12

        /// Waving banner
        static let banner: Int32 = 13

        /// Tesla Model 3 body
        static let teslaCar: Int32 = 14

        /// Car glass canopy
        static let carGlass: Int32 = 15

        /// Car wheel
        static let carWheel: Int32 = 16

        /// Car headlights
        static let headlights: Int32 = 17

        /// Car taillights
        static let taillights: Int32 = 18

        /// LOC flag (pennant shape, waving)
        static let locFlag: Int32 = 19

        /// Orbital satellite (chamfered cube)
        static let satellite: Int32 = 20
    }

    // MARK: - Textures

    enum Textures {
        /// Road surface texture
        static let road: Int32 = 32

        /// Car texture
        static let car: Int32 = 33

        /// Plane texture
        static let plane: Int32 = 34

        /// Font atlas for text rendering
        static let fontAtlas: Int32 = 35

        /// Total number of texture slots
        static let totalCount: Int = 36

        /// Starting index for random building textures
        static let randomStart: Int32 = 22

        /// Ending index for random building textures
        static let randomEnd: Int32 = 31
    }

    // MARK: - Camera

    enum Camera {
        /// Default camera distance in isometric mode
        static let defaultDistance: Float = 60

        /// Minimum camera distance
        static let minDistance: Float = 0.02

        /// Field of view for first-person mode (radians)
        static let firstPersonFOV: Float = 1.2

        /// Field of view for isometric mode (radians)
        static let isometricFOV: Float = 0.75

        /// Fixed pitch angle for isometric view (radians)
        static let isometricPitch: Float = 0.75

        /// Fixed yaw angle for isometric view (radians, ~45 degrees)
        static let isometricYaw: Float = 0.7853982

        /// Near clipping plane (larger value = better depth precision)
        static let nearPlane: Float = 1.0

        /// Far clipping plane
        static let farPlane: Float = 2000
    }

    // MARK: - First-Person Movement

    enum Movement {
        /// Player body height for collision
        static let playerHeight: Float = 3.5

        /// Normal walking speed (units/second)
        static let walkSpeed: Float = 20.0

        /// Sprint speed (units/second)
        static let sprintSpeed: Float = 35.0

        /// Mouse sensitivity (radians/pixel)
        static let mouseSensitivity: Float = 0.002

        /// Maximum pitch angle (prevents gimbal lock)
        static let maxPitch: Float = Float.pi / 2 - 0.1

        /// Gravity acceleration (units/second^2)
        static let gravity: Float = -30.0

        /// Initial jump velocity
        static let jumpVelocity: Float = 18.0

        /// Default eye height when on ground
        static let groundLevel: Float = 3.5

        /// Player collision radius
        static let playerRadius: Float = 0.5
    }

    // MARK: - Grapple

    enum Grapple {
        /// Speed when being pulled by grapple
        static let speed: Float = 80.0

        /// Distance at which grapple stops
        static let arrivalDistance: Float = 3.0
    }

    // MARK: - Plane Physics

    enum PlanePhysics {
        /// Base thrust (no boost)
        static let baseThrust: Float = 12.0

        /// Boosted thrust
        static let boostThrust: Float = 30.0

        /// Gravity for planes
        static let gravity: Float = 9.8

        /// Pitch rate (radians/second)
        static let pitchRate: Float = 1.2

        /// Roll rate (radians/second)
        static let rollRate: Float = 2.0

        /// Maximum pitch angle (radians)
        static let maxPitch: Float = Float.pi / 3

        /// Maximum roll angle (radians)
        static let maxRoll: Float = Float.pi / 2.5

        /// Lift coefficient
        static let liftCoefficient: Float = 0.30

        /// Drag coefficient
        static let dragCoefficient: Float = 0.01

        /// Stall speed
        static let minSpeed: Float = 15.0

        /// Maximum speed (no boost)
        static let maxSpeed: Float = 60.0

        /// Maximum speed (boosting)
        static let boostMaxSpeed: Float = 90.0

        /// Third-person camera distance
        static let thirdPersonDistance: Float = 25.0

        /// Third-person camera height
        static let thirdPersonHeight: Float = 10.0
    }

    // MARK: - Vehicles

    enum Vehicles {
        /// Number of instances per car (body, glass, 4 wheels, headlights, taillights)
        static let instancesPerCar = 8

        /// Tesla Model 3 scale (length, height, width)
        static let carScale = SIMD3<Float>(1.5, 1.1, 3.5)

        /// Wheel radius
        static let wheelRadius: Float = 0.32

        /// Number of car colors in palette
        static let colorPaletteSize: Int = 12

        /// Plane wing scale
        static let planeScale = SIMD3<Float>(7.5, 0.6, 2.5)

        /// Distance planes fly from city
        static let planeOuterPadding: Float = 150.0
    }

    // MARK: - Helicopters

    enum Helicopters {
        /// Flight speed (units/second)
        static let speed: Float = 25.0

        /// Duration hovering over target
        static let hoverDuration: Float = 0.5

        /// Spawn distance from target
        static let spawnDistance: Float = 100.0

        /// Min hover height above target
        static let minHoverHeight: Float = 12.0

        /// Max hover height above target
        static let maxHoverHeight: Float = 35.0

        /// Min starting height
        static let minStartHeight: Float = 40.0

        /// Max starting height
        static let maxStartHeight: Float = 70.0

        /// Hit radius for picking
        static let hitRadius: Float = 4.0

        /// Maximum construction workers
        static let maxWorkers: Int = 100
    }

    // MARK: - Beams

    enum Beams {
        /// Duration of light beam (seconds)
        static let duration: TimeInterval = 2.0

        /// Time for beam to reach full height (seconds)
        static let growTime: Float = 0.15

        /// Maximum beam height
        static let maxHeight: Float = 800.0

        /// Beam width
        static let width: Float = 0.8

        /// Time when fade begins (seconds)
        static let fadeStart: Float = 1.5
    }

    // MARK: - Activity

    enum Activity {
        /// Duration of activity glow effect (seconds)
        static let glowDuration: TimeInterval = 1.4

        /// Duration construction effect shows (seconds)
        static let constructionDuration: TimeInterval = 2.0

        /// Recent delivery tracking duration (seconds)
        static let recentDeliveryDuration: TimeInterval = 3.0
    }

    // MARK: - Git

    enum Git {
        /// Maximum commits to load in history
        static let maxCommitHistory = 200

        /// Cache duration for git status (seconds)
        static let statusCacheDuration: TimeInterval = 30.0
    }

    // MARK: - Search

    enum Search {
        /// Debounce delay for search input (seconds)
        static let debounceDelay: TimeInterval = 0.15
    }

    // MARK: - Signposts

    enum Signposts {
        /// Post height
        static let postHeight: Float = 3.0

        /// Post width
        static let postWidth: Float = 0.4

        /// Sign board height
        static let boardHeight: Float = 1.5

        /// Sign board width
        static let boardWidth: Float = 6.0

        /// Maximum number of sign labels (Metal array limit - 1 for banner)
        static let maxLabels: Int = 2047
    }

    // MARK: - Animation

    enum Animation {
        /// Explosion particle count
        static let explosionParticleCount = 25

        /// Explosion duration (seconds)
        static let explosionDuration: Float = 0.8

        /// Worker spawn delay after explosion (seconds)
        static let workerSpawnDelay: TimeInterval = 0.6
    }
}

// MARK: - Convenience Extensions

extension Constants.Shapes {
    /// Check if a shape ID is a wedge type (needs rotation)
    static func isWedge(_ shapeID: Int32) -> Bool {
        return shapeID == slantX || shapeID == slantZ
    }

    /// Check if a shape ID is a building type
    static func isBuilding(_ shapeID: Int32) -> Bool {
        return shapeID >= standard && shapeID <= cylinder
    }
}
