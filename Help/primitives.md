Primitives
---

ShapeScript has a number of built-in shapes that you can use to quickly construct simple models. These are known as *primitives*, to distinguish them from more complex custom shapes that you can define using [builders](builders.md) and [CSG](csg.md) operations.

## Cube

The `cube` primitive creates a box. You can control the size using the `size` option, which can be used to specify the cube's dimensions individually using 3 values, or using a single value to create a cube with equal sides.

```swift
cube { size 1 1 2 }
```

![Box](images/box.png)

You can also rotate and position the cube using the `orientation` and `position` options, as follows:

```swift
cube {
    size 1 1 2
    position 1 0 0
    orientation 0.25
}
```

The `size`, `position` and `orientation` options are common to all shapes. For more information about these (and other) options, see the [options](options.md) section.

## Sphere

The `sphere` primitive creates a spherical ball. Again, `size` can be used to control the diameter. The following creates a sphere with a diameter of 1 unit (which is the default).

```swift
sphere { size 1 }
```

![Sphere](images/sphere.png)

You may notice that the sphere doesn't look very smooth. As mentioned in the [getting started section](getting-started.md), 3D shapes in ShapeScript are made up of triangles, so curves cannot be represented exactly, only approximated.

You can improve the quality of the sphere by using the `detail` option:

```swift
sphere {
    detail 32
    size 1
}
```

![Smoother sphere](images/smoother-sphere.png)

## Cylinder

The `cylinder` primitive creates a flat-ended cylinder. 

```swift
cylinder { size 1 }
```

![Cylinder](images/cylinder.png)

Like the `sphere` primitive, `cylinder` uses the `detail` command to control its smoothness.

## Cone

The `cone` primitive creates a conical shape, and like `sphere` and `cylinder`, its smoothness is controlled by the `detail` command.

```swift
cone { size 1 }
```

![Cone](images/cone.png)

---
[Index](index.md) | Next: [Options](options.md)
