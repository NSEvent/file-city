import Foundation

struct LayoutRules {
    let maxNodes: Int
    let roadWidth: Int
    let blockPadding: Int
    let minBlockSize: Int
    let maxBlockSize: Int
    let maxBuildingHeight: Int
    let lodDistance: Float

    static let `default` = LayoutRules(
        maxNodes: 20000,
        roadWidth: 2,
        blockPadding: 1,
        minBlockSize: 2,
        maxBlockSize: 12,
        maxBuildingHeight: 64,
        lodDistance: 200
    )
}
