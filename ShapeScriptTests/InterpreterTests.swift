//
//  InterpreterTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 08/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private class TestDelegate: EvaluationDelegate {
    func importGeometry(for _: URL) throws -> Geometry? {
        preconditionFailure()
    }

    func resolveURL(for _: String) -> URL {
        preconditionFailure()
    }

    var log = [String]()
    func debugLog(_ values: [Any?]) {
        log.append(values.map { $0.map { "\($0)" } ?? "nil" }.joined(separator: " "))
    }
}

class InterpreterTests: XCTestCase {
    // MARK: Random numbers

    func testRandomNumberConsistency() {
        let context = EvaluationContext(source: "", delegate: nil)
        XCTAssertEqual(context.random.seed, 0)
        context.random = RandomSequence(seed: .random(in: 0 ..< 10))
        _ = context.random.next()
        let a = context.random.seed

        do {
            // Push a new block context
            let newContext = context.push(.group)
            XCTAssertEqual(a, newContext.random.seed) // test seed is not reset
            _ = newContext.random.next()
            XCTAssertNotEqual(a, newContext.random.seed)
            XCTAssertNotEqual(a, context.random.seed) // test original seed also affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push a new block context
            let newContext = context.push(.group)
            newContext.random = RandomSequence(seed: .random(in: 11 ..< 20))
            _ = newContext.random.next()
            XCTAssertNotEqual(5, newContext.random.seed)
            XCTAssertEqual(a, context.random.seed) // test original seed not affected
        }

        do {
            // Push a new block context
            let newContext = context.pushDefinition()
            XCTAssertEqual(a, newContext.random.seed) // test seed is not reset
            _ = newContext.random.next()
            XCTAssertNotEqual(a, newContext.random.seed)
            XCTAssertNotEqual(a, context.random.seed) // test original seed also affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push definition
            let newContext = context.pushDefinition()
            newContext.random = RandomSequence(seed: 0)
            _ = newContext.random.next()
            XCTAssertNotEqual(5, newContext.random.seed)
            XCTAssertEqual(a, context.random.seed) // test original seed not affected
        }

        do {
            // Push loop context
            context.pushScope { context in
                _ = context.random.next()
            }
            XCTAssertNotEqual(a, context.random.seed) // test original seed is affected
            context.random = RandomSequence(seed: a) // reset seed
        }

        do {
            // Push loop context
            context.pushScope { context in
                context.random = RandomSequence(seed: 99)
            }
            XCTAssertNotEqual(a, context.random.seed) // test original seed is affected
            XCTAssertEqual(context.random.seed, 99) // random state is preserved
            context.random = RandomSequence(seed: a) // reset seed
        }
    }

    // MARK: Name

    func testSetPrimitiveName() throws {
        let program = try parse("""
        cube { name "Foo" }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
    }

    func testSetBuilderName() throws {
        let program = try parse("""
        extrude {
            name "Foo"
            circle
        }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
    }

    func testSetGroupName() throws {
        let program = try parse("""
        group {
            name "Foo"
            cube
            sphere
        }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
        XCTAssertNil(first.children.first?.name)
    }

    func testSetCustomBlockName() throws {
        let program = try parse("""
        define wheel {
            scale 1 0.2 1
            cylinder
        }
        wheel { name "Foo" }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
        XCTAssert(first.children.isEmpty)
    }

    func testSetCustomGroupBlockName() throws {
        let program = try parse("""
        define wheels {
            scale 1 0.2 1
            cylinder
            translate 0 1 0
            cylinder
        }
        wheels { name "Foo" }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
        XCTAssertNil(first.children.first?.name)
        XCTAssertEqual(first.children.count, 2)
    }

    func testSetPathBlockName() throws {
        let program = try parse("""
        define wheel {
            circle
        }
        wheel { name "Foo" }
        """)
        let geometry = try evaluate(program, delegate: nil)
        guard let first = geometry.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(first.name, "Foo")
        XCTAssert(first.children.isEmpty)
    }

    func testNameInvalidAtRoot() {
        let program = """
        name "Foo"
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("name", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testNameInvalidInDefine() {
        let program = """
        define foo {
            name "Foo"
            cube
        }
        foo
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("name", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Option scope

    func testOptionValidInDefine() {
        let program = """
        define foo {
            option bar 5
        }
        foo { bar 5 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testOptionInvalidInPrimitive() {
        let program = """
        cube {
            option foo 5
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("option", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOptionInvalidAtRoot() {
        let program = "option foo 5"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("option", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Position

    func testCumulativePosition() throws {
        let program = """
        translate 1 0 0
        cube { position 1 0 0 }
        """
        let geometry = try evaluate(parse(program), delegate: nil)
        XCTAssertEqual(geometry.first?.transform.offset.x, 2)
    }

    func testPositionValidInPrimitive() {
        let program = """
        cube { position 1 0 0 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInGroup() {
        let program = """
        group { position 1 0 0 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInBuilder() {
        let program = """
        extrude {
            position 1 0 0
            circle
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionValidInCSG() {
        let program = """
        difference {
            position 1 0 0
            cube
            sphere
        }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testPositionInvalidAtRoot() {
        let program = """
        position 1 0 0
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("position", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPositionInvalidInDefine() {
        let program = """
        define foo {
            position 1 0 0
            cube
        }
        foo
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("position", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: Block invocation

    func testInvokePrimitiveWithoutBlock() {
        let program = "cube"
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokeDefineWithoutBlock() {
        let program = """
        define foo {}
        foo
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    func testInvokeBuilderWithoutBlock() {
        let program = "lathe"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("lathe", index: 0, type: "block")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeGroupWithoutBlock() {
        let program = "group"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("group", index: 0, type: "block")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: functions

    func testInvokeMonadicFunction() {
        let program = "print cos pi"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(cos(Double.pi))"])
    }

    func testInvokeMonadicFunctionWithNoArgs() {
        let program = "print cos"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("cos", index: 0, type: "number")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeMonadicFunctionWithTwoArgs() {
        let program = "print cos 1 2"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unexpectedArgument("cos", max: 1)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeDyadicFunction() {
        let program = "print pow 1 2"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(pow(1.0, 2.0))"])
    }

    func testInvokeDyadicFunctionWithNoArgs() {
        let program = "print pow"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("pow", index: 0, type: "pair")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeDyadicFunctionWithOneArg() {
        let program = "print pow 1"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .missingArgument("pow", index: 1, type: "number")? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvokeDyadicFunctionWithThreeArgs() {
        let program = "print pow 1 2 3"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unexpectedArgument("pow", max: 2)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    // MARK: member lookup

    func testTupleVectorLookup() {
        let program = "print (1 0).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(1.0)"])
    }

    func testOutOfBoundsTupleVectorLookup() {
        let program = "print (1 0).z"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(0.0)"])
    }

    func testTupleRGBARedLookup() {
        let program = "print (0.1 0.2 0.3 0.4).red"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(0.1)"])
    }

    func testTupleRGBAlphaLookup() {
        let program = "print (0.1 0.2 0.3).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(1.0)"])
    }

    func testTupleIAGreenLookup() {
        let program = "print (0.1 0.2).green"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(0.1)"])
    }

    func testTupleIAAlphaLookup() {
        let program = "print (0.1 0.2).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["\(0.2)"])
    }

    func testTupleNonexistentLookup() {
        let program = "print (1 2).foo"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("foo", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }

    func testColorWidthLookup() {
        let program = "color 1 0.5\nprint color.width"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            guard case .unknownSymbol("width", _)? = (error as? RuntimeError)?.type else {
                XCTFail()
                return
            }
        }
    }
}
