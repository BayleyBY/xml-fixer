import Foundation

struct SourceRange: Comparable {
    let inPoint: Int
    let outPoint: Int
    var speedFactor: Double = 1.0  // 1.0 = normal, 2.0 = 200% speed, 0.5 = 50% slo-mo

    var length: Int { outPoint - inPoint }

    func mergeableWith(_ other: SourceRange, tolerance: Int = 0) -> Bool {
        return self.inPoint <= other.outPoint + tolerance &&
               other.inPoint <= self.outPoint + tolerance
    }

    func merged(with other: SourceRange) -> SourceRange {
        SourceRange(
            inPoint: min(self.inPoint, other.inPoint),
            outPoint: max(self.outPoint, other.outPoint)
        )
    }

    static func < (lhs: SourceRange, rhs: SourceRange) -> Bool {
        lhs.inPoint < rhs.inPoint
    }
}
