import Foundation

/// Builds static cell features by sampling stand and site polygons at cell centers.
public struct GridBuilder: Sendable {
    public let sites: SiteProfiles

    public init(sites: SiteProfiles) {
        self.sites = sites
    }

    public func build(geometry: GridGeometry, stands: [StandRecord], siteRecords: [SiteRecord]) -> [CellFeatures] {
        let orderedStands = stands.sorted { ($0.layer == .stateForest ? 0 : 1) < ($1.layer == .stateForest ? 0 : 1) }
        let standIndex = SpatialIndex(items: orderedStands, shape: \.shape, bounds: geometry.bbox)
        let siteIndex = SpatialIndex(items: siteRecords, shape: \.shape, bounds: geometry.bbox)
        var cells: [CellFeatures] = []
        var forestMask = [Bool](repeating: false, count: geometry.count)
        for i in 0..<geometry.count {
            let center = geometry.center(of: i)
            let stand = standIndex.first(containing: center)
            let site = siteIndex.first(containing: center)
            guard stand != nil || site != nil else { continue }
            forestMask[i] = true
            cells.append(makeCell(index: i, center: center, stand: stand, site: site))
        }
        let distances = EdgeDistance.compute(mask: forestMask, geometry: geometry)
        return cells.map { cell in
            var c = cell
            c.distEdgeM = distances[cell.cellIndex]
            return c
        }
    }

    private func makeCell(index: Int, center: Coordinate, stand: StandRecord?, site: SiteRecord?) -> CellFeatures {
        let dominant = CodeDictionary.normalizedTreeCode(stand?.dominantSpecies)
        let admixture = sites.speciesCodes(forForestType: site?.forestType).filter { $0 != dominant }
        return CellFeatures(
            cellIndex: index,
            lon: center.lon,
            lat: center.lat,
            standId: stand?.id,
            dominantSpecies: dominant,
            dominantShare: stand?.dominantShare ?? 0,
            admixture: Array(Set(admixture)).sorted(),
            standAge: stand?.age,
            standYear: stand?.dataYear,
            standStructure: stand?.structure,
            siteId: site?.id,
            siteType: sites.normalizedSiteType(site?.siteType),
            geology: site?.geology,
            forestType: site?.forestType,
            arableFormerly: site?.arableFormerly ?? false,
            degraded: site?.degraded ?? false,
            siteYear: site?.dataYear
        )
    }
}

/// Multi-source breadth-first distance from forest cells to the nearest non-forest cell.
enum EdgeDistance {
    static func compute(mask: [Bool], geometry: GridGeometry) -> [Double] {
        var steps = [Int](repeating: Int.max, count: mask.count)
        var queue: [Int] = []
        queue.reserveCapacity(mask.count)
        for (i, isForest) in mask.enumerated() where !isForest {
            steps[i] = 0
            queue.append(i)
        }
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for n in neighbours(of: current, geometry: geometry) where steps[n] == Int.max {
                steps[n] = steps[current] + 1
                queue.append(n)
            }
        }
        return steps.map { $0 == Int.max ? .infinity : max(0, Double($0) - 0.5) * geometry.cellSizeM }
    }

    private static func neighbours(of index: Int, geometry: GridGeometry) -> [Int] {
        let (col, row) = geometry.position(of: index)
        var result: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let c = col + dc, r = row + dr
                if c >= 0, r >= 0, c < geometry.cols, r < geometry.rows {
                    result.append(geometry.index(col: c, row: r))
                }
            }
        }
        return result
    }
}
