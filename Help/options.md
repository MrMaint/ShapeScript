Options
---

All 3D shapes in ShapeScript have a common set of options that you can configure. As implied by the name, options are *optional* - they always have sensible default values that will be used if you don't specify a value.

Some shapes have extra options, specific to that shape. Later you will learn how to define custom options on your own shapes using the [option command](blocks.md#options).

An option is denoted by a name followed by one or more values or expressions inside a shape [block](blocks.md). Different options accept different value types, but typically these will be a number, vector or text. Here are some examples:

```swift
cube {
    detail 5 // a numeric value
    position 1 0 -1 // a vector value
    texture "world.png" // a text value
}
```

## Name

The `name` option allows you to assign a name to a given shape or group, for example:

```swift
cylinder {
    name "Wheel"
    size 1 1 0.1
}
```

The name can contain spaces or punctuation, and is wrapped in double quotes to prevent ambiguity with other symbols (see [literals](literals.md) for details).

The name is not displayed in the app, and currently has no use within ShapeScript itself, however it can be useful for identifying distinct shape components when importing an exported ShapeScript model into another application (see the [export](export.md) section for details).

## Detail

As discussed in the [getting started](getting-started.md) and [primitives](primitives.md) sections, curved shapes cannot be represented exactly using triangles, so they must be approximated to a specified level of detail.

ShapeScript allows you to configure that detail setting using the `detail` command:

```swift
sphere {
    detail 32
}
```
Unlike `name`, `detail` is not actually an option, but a global command. You can change detail level at any point within your ShapeScript file, and it will affect all shapes defined subsequently up to the end of the current [scope](scope.md).

The detail level can be overridden hierarchically, so a `detail` command inside a shape will take precedence over a `detail` command in its containing scope:

```swift
detail 32

sphere { detail 48 } // has detail of 48

cylinder // has detail of 32
```

The `detail` command accepts a single integer value, which represents the number of straight sections used to approximate a circle. This is directly applicable to shapes that have circular sections, such as a sphere or cylinder, as well as to circular [paths](paths.md).

For curved shapes that are not circular, such as a custom [path](paths.md), the relationship between the `detail` value and the number of sections is not quite so straightforward, but typically 1/4 of the `detail` value will be applied to each curved section of the path.

## Transform

Every shape has a position, orientation and size in space. Collectively, these are known as the shape's *transform*, and they can be set using the following options:

- `position x y z`
- `orientation roll yaw pitch`
- `size width height depth`

For more information on how these are used, see the [transforms](transforms.md) section.

## Material

You can set the color and texture of a shape (collectively known as its *material*) by using the `color` and `texture` options. Like `detail`, `color` and `texture` are not actually options, but global commands that can be set anywhere in your ShapeScript file and will apply to all subsequent shapes within the current [scope](scope.md).

For more information about materials, see the [materials](materials.md) section.

---
[Index](index.md) | Next: [Materials](materials.md)
