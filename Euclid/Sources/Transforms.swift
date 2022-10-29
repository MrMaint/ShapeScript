//
//  Transforms.swift
//  Euclid
//
//  Created by Nick Lockwood on 03/07/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
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

import Foundation

/// A combined rotation, position, and scale that can be applied to a 3D object.
///
/// Working with intermediate transform objects instead of directly updating the vertex positions of a mesh
/// is more efficient and avoids a buildup of rounding errors.
public struct Transform: Hashable {
    /// The translation or position component of the transform.
    public var offset: Vector
    /// The rotation or orientation component of the transform.
    public var rotation: Rotation
    /// The size or scale component of the transform.
    public var scale: Vector {
        didSet { scale = scale.clamped() }
    }

    /// Creates a new transform.
    /// - Parameters:
    ///   - offset: The translation or position component of the transform. Defaults to zero (no offset).
    ///   - rotation: The translation or position component of the transform. Defaults to identity (no rotation).
    ///   - scale: The scaling component of the transform. Defaults to one (no scale adjustment).
    public init(offset: Vector? = nil, rotation: Rotation? = nil, scale: Vector? = nil) {
        self.offset = offset ?? .zero
        self.rotation = rotation ?? .identity
        self.scale = scale?.clamped() ?? .one
    }
}

extension Transform: Codable {
    private enum CodingKeys: CodingKey {
        case offset, rotation, scale
    }

    /// Creates a new transform by decoding from the given decoder.
    /// - Parameter decoder: The decoder to read data from.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let offset = try container.decodeIfPresent(Vector.self, forKey: .offset)
        let rotation = try container.decodeIfPresent(Rotation.self, forKey: .rotation)
        let scale = try container.decodeIfPresent(Vector.self, forKey: .scale)
        self.init(offset: offset, rotation: rotation, scale: scale)
    }

    /// Encodes this transform into the given encoder.
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try offset.isEqual(to: .zero) ? () : container.encode(offset, forKey: .offset)
        try rotation.isIdentity ? () : container.encode(rotation, forKey: .rotation)
        try scale.isEqual(to: .one) ? () : container.encode(scale, forKey: .scale)
    }
}

public extension Transform {
    /// The identity transform (i.e. no transform).
    static let identity = Transform()

    /// Transform has no effect.
    var isIdentity: Bool {
        rotation.isIdentity && offset.isEqual(to: .zero) && scale.isEqual(to: .one)
    }

    /// Does the transform apply a mirror operation (negative scale).
    /// - Parameter v: An offset vector to apply to the transform.
    var isFlipped: Bool {
        var flipped = scale.x < 0
        if scale.y < 0 { flipped = !flipped }
        if scale.z < 0 { flipped = !flipped }
        return flipped
    }

    /// Translates the transform.
    /// - Parameter v: An offset vector to apply to the transform.
    mutating func translate(by v: Vector) {
        offset = offset + v.scaled(by: scale).rotated(by: rotation)
    }

    /// Rotates the transform.
    /// - Parameter r: A rotation to apply to the transform.
    mutating func rotate(by r: Rotation) {
        rotation *= r
    }

    /// Scales the transform.
    /// - Parameter v: A vector scale factor.
    mutating func scale(by v: Vector) {
        scale = scale.scaled(by: v)
    }

    /// Combines two transforms to get the cumulative transform.
    static func * (lhs: Transform, rhs: Transform) -> Transform {
        var result = rhs
        result.translate(by: lhs.offset)
        result.scale(by: lhs.scale)
        result.rotation *= lhs.rotation
        return result
    }
}

public extension Mesh {
    /// Returns a translated copy of the mesh.
    /// - Parameter v: An offset vector to apply to the mesh.
    func translated(by v: Vector) -> Mesh {
        v.isEqual(to: .zero) ? self : Mesh(
            unchecked: polygons.translated(by: v),
            bounds: boundsIfSet?.translated(by: v),
            isConvex: isKnownConvex,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }

    /// Returns a rotated copy of the mesh.
    /// - Parameter r: A rotation to apply to the mesh.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Mesh {
        r.isIdentity ? self : Mesh(
            unchecked: polygons.rotated(by: r),
            bounds: nil,
            isConvex: isKnownConvex,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }

    /// Returns a rotated copy of the mesh.
    /// - Parameter q: A quaternion to apply to the mesh.
    func rotated(by q: Quaternion) -> Mesh {
        q.isIdentity ? self : Mesh(
            unchecked: polygons.rotated(by: q),
            bounds: nil,
            isConvex: isKnownConvex,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }

    /// Returns a scaled copy of the mesh.
    /// - Parameter v: A scale vector to apply to the mesh.
    func scaled(by v: Vector) -> Mesh {
        if v.x == v.y, v.y == v.z {
            // optimization - avoids scaling normals
            return scaled(by: v.x)
        }
        return Mesh(
            unchecked: polygons.scaled(by: v),
            bounds: boundsIfSet?.scaled(by: v),
            isConvex: isKnownConvex && v.x > 0 && v.y > 0 && v.y > 0,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }

    /// Returns a scaled copy of the mesh.
    /// - Parameter f: A scale factor to apply to the mesh.
    func scaled(by f: Double) -> Mesh {
        f.isEqual(to: 1, withPrecision: epsilon) ? self : Mesh(
            unchecked: polygons.scaled(by: f),
            bounds: boundsIfSet?.scaled(by: f),
            isConvex: isKnownConvex && f > 0,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }

    /// Returns a transformed copy of the mesh.
    /// - Parameter t: A transform to apply to the mesh.
    func transformed(by t: Transform) -> Mesh {
        t.isIdentity ? self : Mesh(
            unchecked: polygons.transformed(by: t),
            bounds: boundsIfSet.flatMap {
                t.rotation.isIdentity ? $0.transformed(by: t) : nil
            },
            isConvex: isKnownConvex,
            isWatertight: watertightIfSet,
            submeshes: submeshesIfEmpty
        )
    }
}

public extension Polygon {
    /// Returns a translated copy of the polygon.
    /// - Parameter v: An offset vector to apply to the polygon.
    func translated(by v: Vector) -> Polygon {
        v.isEqual(to: .zero) ? self : Polygon(
            unchecked: vertices.translated(by: v),
            normal: plane.normal,
            isConvex: isConvex,
            material: material
        )
    }

    /// Returns a rotated copy of the polygon.
    /// - Parameter r: A rotation to apply to the polygon.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Polygon {
        r.isIdentity ? self : Polygon(
            unchecked: vertices.rotated(by: r),
            normal: plane.normal.rotated(by: r),
            isConvex: isConvex,
            material: material
        )
    }

    /// Returns a rotated copy of the polygon.
    /// - Parameter q: A quaternion to apply to the polygon.
    func rotated(by q: Quaternion) -> Polygon {
        q.isIdentity ? self : Polygon(
            unchecked: vertices.rotated(by: q),
            normal: plane.normal.rotated(by: q),
            isConvex: isConvex,
            material: material
        )
    }

    /// Returns a scaled copy of the polygon.
    /// - Parameter f: A scale vector to apply to the polygon.
    func scaled(by v: Vector) -> Polygon {
        if v.x == v.y, v.y == v.z {
            // optimization - avoids scaling normals
            return scaled(by: v.x)
        }

        let v = v.clamped()
        var flipped = v.x < 0
        if v.y < 0 { flipped = !flipped }
        if v.z < 0 { flipped = !flipped }

        let vertices = self.vertices.scaled(by: v)
        let vn = Vector(1 / v.x, 1 / v.y, 1 / v.z)
        return Polygon(
            unchecked: flipped ? vertices.reversed() : vertices,
            normal: plane.normal.scaled(by: vn).normalized(),
            isConvex: nil,
            material: material
        )
    }

    /// Returns a scaled copy of the polygon.
    /// - Parameter f: A scale factor to apply to the polygon.
    func scaled(by f: Double) -> Polygon {
        if f.isEqual(to: 1, withPrecision: epsilon) {
            return self
        }
        let f = f.clamped()
        let polygon = Polygon(
            unchecked: vertices.scaled(by: f),
            normal: plane.normal,
            isConvex: isConvex,
            material: material
        )
        return f < 0 ? polygon.inverted() : polygon
    }

    /// Returns a transformed copy of the polygon.
    /// - Parameter t: A transform to apply to the polygon.
    func transformed(by t: Transform) -> Polygon {
        scaled(by: t.scale).rotated(by: t.rotation).translated(by: t.offset)
    }
}

internal extension Collection where Element == Polygon {
    func translated(by v: Vector) -> [Polygon] {
        v.isEqual(to: .zero) ? Array(self) : map { $0.translated(by: v) }
    }

    @_disfavoredOverload
    func rotated(by r: Rotation) -> [Polygon] {
        r.isIdentity ? Array(self) : map { $0.rotated(by: r) }
    }

    func rotated(by q: Quaternion) -> [Polygon] {
        q.isIdentity ? Array(self) : map { $0.rotated(by: q) }
    }

    func scaled(by v: Vector) -> [Polygon] {
        v.isEqual(to: .one) ? Array(self) : map { $0.scaled(by: v) }
    }

    func scaled(by f: Double) -> [Polygon] {
        f.isEqual(to: 1, withPrecision: epsilon) ? Array(self) : map { $0.scaled(by: f) }
    }

    func transformed(by t: Transform) -> [Polygon] {
        t.isIdentity ? Array(self) : map { $0.transformed(by: t) }
    }
}

public extension Vertex {
    /// Returns a translated copy of the vertex.
    /// - Parameter v: An offset vector to apply to the vertex.
    func translated(by v: Vector) -> Vertex {
        Vertex(unchecked: position + v, normal, texcoord, color)
    }

    /// Returns a rotated copy of the vertex.
    /// - Parameter r: A rotation to apply to the vertex.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Vertex {
        Vertex(
            unchecked: position.rotated(by: r),
            normal.rotated(by: r),
            texcoord,
            color
        )
    }

    /// Returns a rotated copy of the vertex.
    /// - Parameter q: A quaternion to apply to the vertex.
    func rotated(by q: Quaternion) -> Vertex {
        Vertex(
            unchecked: position.rotated(by: q),
            normal.rotated(by: q),
            texcoord,
            color
        )
    }

    /// Returns a scaled copy of the vertex.
    /// - Parameter v: A scale vector to apply to the vertex.
    func scaled(by v: Vector) -> Vertex {
        let vn = Vector(1 / v.x, 1 / v.y, 1 / v.z)
        return Vertex(
            unchecked: position.scaled(by: v),
            normal.scaled(by: vn).normalized(),
            texcoord,
            color
        )
    }

    /// Returns a scaled copy of the vertex.
    /// - Parameter f: A scale factor to apply to the vertex.
    func scaled(by f: Double) -> Vertex {
        Vertex(unchecked: position * f, normal, texcoord, color)
    }

    /// Returns a transformed copy of the vertex.
    /// - Parameter t: A transform to apply to the vertex.
    func transformed(by t: Transform) -> Vertex {
        scaled(by: t.scale).rotated(by: t.rotation).translated(by: t.offset)
    }
}

internal extension Collection where Element == Vertex {
    func translated(by v: Vector) -> [Vertex] {
        v.isEqual(to: .zero) ? Array(self) : map { $0.translated(by: v) }
    }

    @_disfavoredOverload
    func rotated(by r: Rotation) -> [Vertex] {
        r.isIdentity ? Array(self) : map { $0.rotated(by: r) }
    }

    func rotated(by q: Quaternion) -> [Vertex] {
        q.isIdentity ? Array(self) : map { $0.rotated(by: q) }
    }

    func scaled(by v: Vector) -> [Vertex] {
        v.isEqual(to: .one) ? Array(self) : map { $0.scaled(by: v) }
    }

    func scaled(by f: Double) -> [Vertex] {
        f.isEqual(to: 1, withPrecision: epsilon) ? Array(self) : map { $0.scaled(by: f) }
    }

    func transformed(by t: Transform) -> [Vertex] {
        t.isIdentity ? Array(self) : map { $0.transformed(by: t) }
    }
}

public extension Vector {
    /// Returns a translated copy of the vector.
    /// - Parameter v: An offset vector to apply to the original vector.
    func translated(by v: Vector) -> Vector {
        self + v
    }

    /// Returns a rotated copy of the vector.
    /// - Parameter r: A rotation to apply to the vector.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Vector {
        rotated(by: Quaternion(r))
    }

    /// Returns a rotated copy of the vector.
    /// - Parameter q: A quaternion to apply to the vector.
    func rotated(by q: Quaternion) -> Vector {
        let qv = Vector(q.x, q.y, q.z)
        let uv = qv.cross(self)
        let uuv = qv.cross(uv)
        return self + (uv * 2 * q.w) + (uuv * 2)
    }

    /// Returns a scaled copy of the vector.
    /// - Parameter v: A scale vector to apply to the vector.
    func scaled(by v: Vector) -> Vector {
        Vector(x * v.x, y * v.y, z * v.z)
    }

    /// Returns a transformed copy of the vector.
    /// - Parameter t: A transform to apply to the vector.
    func transformed(by t: Transform) -> Vector {
        scaled(by: t.scale).rotated(by: t.rotation) + t.offset
    }
}

internal extension Collection where Element == Vector {
    func translated(by v: Vector) -> [Vector] {
        v.isEqual(to: .zero) ? Array(self) : map { $0.translated(by: v) }
    }

    @_disfavoredOverload
    func rotated(by r: Rotation) -> [Vector] {
        map { $0.rotated(by: Quaternion(r)) }
    }

    func rotated(by q: Quaternion) -> [Vector] {
        map { $0.rotated(by: q) }
    }

    func scaled(by v: Vector) -> [Vector] {
        map { $0.scaled(by: v) }
    }

    func scaled(by f: Double) -> [Vector] {
        map { $0 * f }
    }

    func transformed(by t: Transform) -> [Vector] {
        map { $0.transformed(by: t) }
    }
}

public extension PathPoint {
    /// Returns a translated copy of the path point.
    /// - Parameter v: An offset vector to apply to the path point.
    func translated(by v: Vector) -> PathPoint {
        PathPoint(
            position + v,
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }

    /// Returns a rotated copy of the path point.
    /// - Parameter r: A rotation to apply to the path point.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> PathPoint {
        PathPoint(
            position.rotated(by: r),
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }

    /// Returns a rotated copy of the path point.
    /// - Parameter q: A quaternion to apply to the path point.
    func rotated(by q: Quaternion) -> PathPoint {
        PathPoint(
            position.rotated(by: q),
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }

    /// Returns a scaled copy of the path point.
    /// - Parameter v: A scale vector to apply to the path point.
    func scaled(by v: Vector) -> PathPoint {
        PathPoint(
            position.scaled(by: v),
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }

    /// Returns a scaled copy of the path point.
    /// - Parameter f: A scale factor to apply to the path point.
    func scaled(by f: Double) -> PathPoint {
        PathPoint(
            position * f,
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }

    /// Returns a transformed copy of the path point.
    /// - Parameter t: A transform to apply to the path point.
    func transformed(by t: Transform) -> PathPoint {
        PathPoint(
            position.transformed(by: t),
            texcoord: texcoord,
            color: color,
            isCurved: isCurved
        )
    }
}

internal extension Collection where Element == PathPoint {
    func translated(by v: Vector) -> [PathPoint] {
        v.isEqual(to: .zero) ? Array(self) : map { $0.translated(by: v) }
    }

    @_disfavoredOverload
    func rotated(by r: Rotation) -> [PathPoint] {
        r.isIdentity ? Array(self) : map { $0.rotated(by: r) }
    }

    func rotated(by q: Quaternion) -> [PathPoint] {
        q.isIdentity ? Array(self) : map { $0.rotated(by: q) }
    }

    func scaled(by v: Vector) -> [PathPoint] {
        v.isEqual(to: .one) ? Array(self) : map { $0.scaled(by: v) }
    }

    func scaled(by f: Double) -> [PathPoint] {
        f.isEqual(to: 1, withPrecision: epsilon) ? Array(self) : map { $0.scaled(by: f) }
    }

    func transformed(by t: Transform) -> [PathPoint] {
        t.isIdentity ? Array(self) : map { $0.transformed(by: t) }
    }
}

public extension Path {
    /// Returns a translated copy of the path.
    /// - Parameter v: An offset vector to apply to the path.
    func translated(by v: Vector) -> Path {
        Path(
            unchecked: points.translated(by: v),
            plane: plane?.translated(by: v), subpathIndices: subpathIndices
        )
    }

    /// Returns a rotated copy of the path.
    /// - Parameter r: A rotation to apply to the path.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Path {
        Path(
            unchecked: points.rotated(by: r),
            plane: plane?.rotated(by: r), subpathIndices: subpathIndices
        )
    }

    /// Returns a rotated copy of the path.
    /// - Parameter q: A quaternion to apply to the path.
    func rotated(by q: Quaternion) -> Path {
        Path(
            unchecked: points.rotated(by: q),
            plane: plane?.rotated(by: q), subpathIndices: subpathIndices
        )
    }

    /// Returns a scaled copy of the path.
    /// - Parameter f: A scale vector to apply to the path.
    func scaled(by v: Vector) -> Path {
        let v = v.clamped()
        return Path(
            unchecked: points.scaled(by: v),
            plane: plane?.scaled(by: v), subpathIndices: subpathIndices
        )
    }

    /// Returns a scaled copy of the path.
    /// - Parameter f: A scale factor to apply to the path.
    func scaled(by f: Double) -> Path {
        let f = f.clamped()
        return Path(
            unchecked: points.scaled(by: f),
            plane: plane?.scaled(by: f), subpathIndices: subpathIndices
        )
    }

    /// Returns a transformed copy of the path.
    /// - Parameter t: A transform to apply to the path.
    func transformed(by t: Transform) -> Path {
        Path(
            unchecked: points.transformed(by: t),
            plane: plane?.transformed(by: t), subpathIndices: subpathIndices
        )
    }
}

public extension Plane {
    /// Returns a translated copy of the plane.
    /// - Parameter v: An offset vector to apply to the plane.
    func translated(by v: Vector) -> Plane {
        Plane(unchecked: normal, pointOnPlane: normal * w + v)
    }

    /// Returns a rotated copy of the plane.
    /// - Parameter r: A quaternion to apply to the plane.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Plane {
        Plane(unchecked: normal.rotated(by: r), w: w)
    }

    /// Returns a rotated copy of the plane.
    /// - Parameter q: A quaternion to apply to the plane.
    func rotated(by q: Quaternion) -> Plane {
        Plane(unchecked: normal.rotated(by: q), w: w)
    }

    /// Returns a scaled copy of the plane.
    /// - Parameter v: A scale vector to apply to the plane.
    func scaled(by v: Vector) -> Plane {
        if v.x == v.y, v.y == v.z {
            return scaled(by: v.x)
        }
        let v = v.clamped()
        let p = (normal * w).scaled(by: v)
        let vn = Vector(1 / v.x, 1 / v.y, 1 / v.z)
        return Plane(unchecked: normal.scaled(by: vn).normalized(), pointOnPlane: p)
    }

    /// Returns a scaled copy of the plane.
    /// - Parameter f: A scale factor to apply to the plane.
    func scaled(by f: Double) -> Plane {
        Plane(unchecked: normal, w: w * f.clamped())
    }

    /// Returns a transformed copy of the plane.
    /// - Parameter t: A transform to apply to the plane.
    func transformed(by t: Transform) -> Plane {
        scaled(by: t.scale).rotated(by: t.rotation).translated(by: t.offset)
    }
}

public extension Bounds {
    /// Returns a translated copy of the bounds.
    /// - Parameter v: An offset vector to apply to the bounds.
    func translated(by v: Vector) -> Bounds {
        Bounds(min: min + v, max: max + v)
    }

    /// Returns a rotated copy of the bounds.
    /// - Parameter r: A rotation to apply to the bounds.
    ///
    /// > Note: Because a bounds must be axially-aligned, rotating by an angle that is not a multiple of
    /// 90 degrees will result in the bounds being increased in size. Rotating it back again will not reduce
    /// the size, so this is a potentially irreversible operation. In general, after rotating a shape it is better
    /// to recalculate the bounds rather than trying to rotate the previous bounds.
    @_disfavoredOverload
    func rotated(by r: Rotation) -> Bounds {
        isEmpty ? self : Bounds(points: corners.rotated(by: r))
    }

    /// Returns a rotated copy of the bounds.
    /// - Parameter q: A quaternion to apply to the bounds.
    ///
    /// > Note: Because a bounds must be axially-aligned, rotating by an angle that is not a multiple of
    /// 90 degrees will result in the bounds being increased in size. Rotating it back again will not reduce
    /// the size, so this is a potentially irreversible operation. In general, after rotating a shape it is better
    /// to recalculate the bounds rather than trying to rotate the previous bounds.
    func rotated(by q: Quaternion) -> Bounds {
        isEmpty ? self : Bounds(points: corners.rotated(by: q))
    }

    /// Returns a scaled copy of the bounds.
    /// - Parameter v: A scale vector to apply to the bounds.
    func scaled(by v: Vector) -> Bounds {
        let v = v.clamped()
        return isEmpty ? self : Bounds(min.scaled(by: v), max.scaled(by: v))
    }

    /// Returns a scaled copy of the bounds.
    /// - Parameter f: A scale factor to apply to the bounds.
    func scaled(by f: Double) -> Bounds {
        let f = f.clamped()
        return isEmpty ? self : Bounds(min * f, max * f)
    }

    /// Returns a transformed copy of the bounds.
    /// - Parameter t: A transform to apply to the bounds.
    func transformed(by t: Transform) -> Bounds {
        scaled(by: t.scale).rotated(by: t.rotation).translated(by: t.offset)
    }
}

// extension Array: Transformable where Element: Transformable {
//    public func translated(by v: Vector) -> [Element] {
//        v.isEqual(to: .zero) ? self : map { $0.translated(by: v) }
//    }
//
//    public func rotated(by q: Quaternion) -> [Element] {
//        q.isIdentity ? self : map { $0.rotated(by: q) }
//    }
//
//    public func scaled(by v: Vector) -> [Element] {
//        v.isEqual(to: .one) ? self : map { $0.scaled(by: v) }
//    }
//
//    public func scaled(by f: Double) -> [Element] {
//        f.isEqual(to: 1, withPrecision: epsilon) ? self : map { $0.scaled(by: f) }
//    }
//
//    public func transformed(by t: Transform) -> [Element] {
//        t.isIdentity ? self : map { $0.transformed(by: t) }
//    }
// }

private extension Double {
    func clamped() -> Double {
        self < 0 ? min(self, -scaleLimit) : max(self, scaleLimit)
    }
}

private extension Vector {
    func clamped() -> Self {
        Self(x.clamped(), y.clamped(), z.clamped())
    }
}
