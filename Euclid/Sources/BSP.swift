//
//  BSP.swift
//  Euclid
//
//  Created by Nick Lockwood on 20/01/2020.
//  Copyright © 2020 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/Euclid
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

struct BSP {
    private var nodes: [BSPNode]

    enum ClipRule {
        case greaterThan
        case greaterThanEqual
        case lessThan
        case lessThanEqual
    }

    init(_ mesh: Mesh) {
        self.nodes = [BSPNode]()
        initialize(mesh.polygons, isConvex: mesh.isConvex)
    }

    func clip(_ polygons: [Polygon], _ keeping: ClipRule) -> [Polygon] {
        var id = 0
        return clip(polygons.map { $0.with(id: 0) }, keeping, &id)
    }
}

// See https://github.com/wangyi-fudan/wyhash/
private struct DeterministicRNG: RandomNumberGenerator {
    private var seed: UInt64 = 0

    mutating func next() -> UInt64 {
        seed &+= 0xA0761D6478BD642F
        let result = seed.multipliedFullWidth(by: seed ^ 0xE7037ED1A0B428DB)
        return result.high ^ result.low
    }
}

private class BSPNode {
    var front: Int = 0
    var back: Int = 0
    var polygons = [Polygon]()
    var plane: Plane

    init(plane: Plane) {
        self.plane = plane
    }

    init(polygon: Polygon) {
        self.polygons = [polygon]
        self.plane = polygon.plane
    }
}

private extension BSP {
    mutating func initialize(_ polygons: [Polygon], isConvex: Bool) {
        nodes.reserveCapacity(polygons.count)
        var rng = DeterministicRNG()

        guard isConvex else {
            guard !polygons.isEmpty else {
                return
            }
            // Randomly shuffle polygons to reduce average number of splits
            let polygons = polygons.shuffled(using: &rng)
            nodes.append(BSPNode(plane: polygons[0].plane))
            insert(polygons)
            return
        }

        // Sort polygons by plane
        let polygons = polygons.sortedByPlane()

        // Create nodes
        var parent: BSPNode?
        for polygon in polygons {
            if let parent = parent, polygon.plane.isEqual(to: parent.plane) {
                parent.polygons.append(polygon)
                continue
            }
            let node = BSPNode(polygon: polygon)
            nodes.append(node)
            parent = node
        }

        // Randomly shuffle nodes to reduce average number of splits
        nodes.shuffle(using: &rng)

        // Use fast BSP construction
        for i in 0 ..< nodes.count - 1 {
            nodes[i].back = i + 1
        }
    }

    mutating func insert(_ polygons: [Polygon]) {
        var stack = [(node: nodes[0], polygons: polygons)]
        while let (node, polygons) = stack.popLast() {
            var front = [Polygon](), back = [Polygon]()
            for polygon in polygons {
                switch polygon.compare(with: node.plane) {
                case .coplanar:
                    if node.plane.normal.dot(polygon.plane.normal) > 0 {
                        node.polygons.append(polygon)
                    } else {
                        back.append(polygon)
                    }
                case .front:
                    front.append(polygon)
                case .back:
                    back.append(polygon)
                case .spanning:
                    var id = 0
                    polygon.split(spanning: node.plane, &front, &back, &id)
                }
            }
            if let first = front.first {
                let next: BSPNode
                if node.front > 0 {
                    next = nodes[node.front]
                } else {
                    next = BSPNode(plane: first.plane)
                    node.front = nodes.count
                    nodes.append(next)
                }
                stack.append((next, front))
            }
            if let first = back.first {
                let next: BSPNode
                if node.back > 0 {
                    next = nodes[node.back]
                } else {
                    next = BSPNode(plane: first.plane)
                    node.back = nodes.count
                    nodes.append(next)
                }
                stack.append((next, back))
            }
        }
    }

    func clip(
        _ polygons: [Polygon],
        _ keeping: BSP.ClipRule,
        _ id: inout Int
    ) -> [Polygon] {
        guard !nodes.isEmpty else {
            return polygons
        }
        var total = [Polygon]()
        func addPolygons(_ polygons: [Polygon]) {
            for a in polygons {
                guard a.id != 0 else {
                    total.append(a)
                    continue
                }
                var a = a
                for i in total.indices.reversed() {
                    let b = total[i]
                    if a.id == b.id, let c = a.merge(unchecked: b, ensureConvex: false) {
                        a = c
                        total.remove(at: i)
                    }
                }
                total.append(a)
            }
        }
        let keepFront = [.greaterThan, .greaterThanEqual].contains(keeping)
        var stack = [(node: nodes[0], polygons: polygons)]
        while let (node, polygons) = stack.popLast() {
            var coplanar = [Polygon](), front = [Polygon](), back = [Polygon]()
            for polygon in polygons {
                polygon.split(along: node.plane, &coplanar, &front, &back, &id)
            }
            for polygon in coplanar {
                switch keeping {
                case .greaterThan, .lessThanEqual:
                    polygon.clip(to: node.polygons, &back, &front, &id)
                case .greaterThanEqual, .lessThan:
                    if node.plane.normal.dot(polygon.plane.normal) > 0 {
                        front.append(polygon)
                    } else {
                        polygon.clip(to: node.polygons, &back, &front, &id)
                    }
                }
            }
            if !front.isEmpty {
                if node.front > 0 {
                    stack.append((nodes[node.front], front))
                } else {
                    addPolygons(keepFront ? front : [])
                }
            }
            if !back.isEmpty {
                if node.back > 0 {
                    stack.append((nodes[node.back], back))
                } else {
                    addPolygons(keepFront ? [] : back)
                }
            }
        }
        return total
    }
}
