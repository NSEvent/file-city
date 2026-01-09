import Foundation
import simd

struct CityBlock: Identifiable, Hashable {
    let id: UUID
    let nodeID: UUID
    let name: String
    let position: SIMD3<Float>
    let footprint: SIMD2<Int32>
    let height: Int32
    let materialID: Int32
    let textureIndex: Int32
    let shapeID: Int32
    let isPinned: Bool
    let isGitRepo: Bool
    let isGitClean: Bool
}

extension CityBlock {
    func withGitClean(_ isGitClean: Bool) -> CityBlock {
        CityBlock(
            id: id,
            nodeID: nodeID,
            name: name,
            position: position,
            footprint: footprint,
            height: height,
            materialID: materialID,
            textureIndex: textureIndex,
            shapeID: shapeID,
            isPinned: isPinned,
            isGitRepo: isGitRepo,
            isGitClean: isGitClean
        )
    }
}

// MARK: - Computed Properties

extension CityBlock {
    /// The Y coordinate at the base top (without shape deformation)
    var baseTopY: Float {
        position.y + Float(height)
    }

    /// The visual top Y coordinate accounting for shape deformations
    /// Taper/pyramid/wedge shapes extend above the base height
    var visualTopY: Float {
        let spireBoost: Float
        switch shapeID {
        case Constants.Shapes.slantX, Constants.Shapes.slantZ:
            spireBoost = Float(height) * 0.75
        case Constants.Shapes.taper, Constants.Shapes.pyramid:
            spireBoost = Float(height) * 0.5
        default:
            spireBoost = 0
        }
        return baseTopY + spireBoost
    }

    /// Whether this block's shape is a wedge type (needs rotation)
    var isWedge: Bool {
        Constants.Shapes.isWedge(shapeID)
    }

    /// Grid key for spatial indexing (quantized X/Z position)
    var gridKey: GridKey {
        GridKey(x: Int(position.x * 10), z: Int(position.z * 10))
    }

    /// Footprint size as floats
    var footprintFloat: SIMD2<Float> {
        SIMD2<Float>(Float(footprint.x), Float(footprint.y))
    }
}

// MARK: - Grid Key for Spatial Indexing

/// A hashable key for grouping blocks by grid position
struct GridKey: Hashable {
    let x: Int
    let z: Int
}

// MARK: - Spatial Index

/// A spatial index for efficient lookup of blocks by position
struct BlockSpatialIndex {
    private var blocksByGrid: [GridKey: [CityBlock]] = [:]

    init(blocks: [CityBlock]) {
        for block in blocks {
            let key = block.gridKey
            blocksByGrid[key, default: []].append(block)
        }
    }

    /// Get all blocks at the same X/Z location
    func blocks(at key: GridKey) -> [CityBlock] {
        return blocksByGrid[key] ?? []
    }

    /// Get the topmost block at a location
    func topmostBlock(at key: GridKey) -> CityBlock? {
        let blocks = self.blocks(at: key)
        return blocks.max { $0.visualTopY < $1.visualTopY }
    }

    /// Get the maximum visual height at a location
    func maxHeight(at key: GridKey) -> Float {
        return topmostBlock(at: key)?.visualTopY ?? 0
    }
}
