//
//  EvaluationContext.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 18/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

// MARK: Implementation

class EvaluationContext {
    private class ImportCache {
        var store = [URL: Program]()
    }

    private weak var delegate: EvaluationDelegate?
    private var symbols = Symbols.root
    private var userSymbols = Symbols()
    private let importCache: ImportCache
    private(set) var baseURL: URL?

    var source: String
    var sourceIndex: String.Index?

    var material: Material = .default
    var transform = Transform.identity
    var childTransform = Transform.identity
    var childTypes: Set<ValueType> = [.mesh]
    var children = [Value]()
    var name: String?
    var random: RandomSequence
    var detail = 16
    var font: String?
    var opacity = 1.0

    var sourceLocation: SourceLocation? {
        return sourceIndex.map {
            SourceLocation(
                at: source.lineAndColumn(at: $0).line,
                in: baseURL
            )
        }
    }

    init(source: String, delegate: EvaluationDelegate?) {
        self.source = source
        self.delegate = delegate
        importCache = ImportCache()
        random = RandomSequence(seed: 0)
    }

    private init(parent: EvaluationContext) {
        // preserve
        source = parent.source
        sourceIndex = parent.sourceIndex
        baseURL = parent.baseURL
        delegate = parent.delegate
        symbols = parent.symbols
        userSymbols = parent.userSymbols
        importCache = parent.importCache
        material = parent.material
        childTypes = parent.childTypes
        random = parent.random
        detail = parent.detail
        font = parent.font
        // opacity is cumulative
        opacity = parent.material.opacity
        // reset
        transform = .identity
        childTransform = .identity
        children = []
    }

    func push(_ type: BlockType) -> EvaluationContext {
        let new = EvaluationContext(parent: self)
        new.childTypes = type.childTypes
        new.symbols = type.symbols
        for name in type.symbols.keys {
            new.userSymbols[name] = nil
        }
        return new
    }

    func pushScope(_ block: (EvaluationContext) throws -> Void) rethrows {
        let oldSourceIndex = sourceIndex
        let oldSymbols = userSymbols
        try block(self)
        sourceIndex = oldSourceIndex
        userSymbols = oldSymbols
    }

    func pushDefinition() -> EvaluationContext {
        let new = EvaluationContext(parent: self)
        new.name = name
        new.transform = transform
        new.opacity = opacity
        new.childTypes = [.mesh, .path, .paths]
        new.symbols = .definition
        return new
    }
}

// MARK: Symbols

typealias Getter = (EvaluationContext) throws -> Value
typealias Setter = (Value, EvaluationContext) throws -> Void

enum Symbol {
    case command(ValueType, (Value, EvaluationContext) throws -> Value)
    case property(ValueType, Setter, Getter)
    case block(BlockType, Getter)
    case constant(Value)
}

typealias Symbols = [String: Symbol]

extension EvaluationContext {
    func symbol(for name: String) -> Symbol? {
        return userSymbols[name] ?? symbols[name]
    }

    func define(_ name: String, as symbol: Symbol) {
        userSymbols[name] = symbol
    }

    var expressionSymbols: [String] {
        return Array(symbols.merging(userSymbols) { $1 }.keys)
    }

    var commandSymbols: [String] {
        return expressionSymbols.compactMap {
            if case .constant? = symbol(for: $0) {
                return nil
            }
            return $0
        } + Keyword.allCases.map { $0.rawValue }
    }

    func value(for name: String) -> Value? {
        if case let .constant(value)? = symbol(for: name) {
            return value
        }
        return nil
    }
}

// MARK: Debugging

extension EvaluationContext {
    func debugLog(_ values: [Any?]) {
        delegate?.debugLog(values)
    }
}

// MARK: External file access

extension EvaluationContext {
    func resolveURL(for path: String) throws -> URL {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            // TODO: should this be a different error type, like "empty path not allowed"?
            throw RuntimeErrorType.fileNotFound(for: path, at: nil)
        }
        let documentRelativePath = baseURL.map {
            URL(fileURLWithPath: path, relativeTo: $0).path
        } ?? path
        guard let url = delegate?.resolveURL(for: documentRelativePath) else {
            // TODO: should this be a different error type, like "delegate not available"?
            throw RuntimeErrorType.fileNotFound(for: path, at: nil)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            let directory = url.deletingLastPathComponent()
            throw RuntimeErrorType.fileAccessRestricted(for: path, at: directory)
        }
        return url
    }

    func importModel(at path: String) throws {
        let url = try resolveURL(for: path)
        let program: Program
        if let entry = importCache.store[url] {
            program = entry
        } else if url.pathExtension == "shape", // TODO: async source loading?
            let source = try? String(contentsOf: url, encoding: .utf8)
        {
            do {
                program = try parse(source)
                importCache.store[url] = program
            } catch {
                throw RuntimeErrorType.importError(ImportError(error), for: path, in: source)
            }
        } else {
            do {
                if let geometry = try delegate?.importGeometry(for: url)?.with(
                    transform: childTransform,
                    material: material,
                    sourceLocation: sourceLocation
                ) {
                    children.append(.mesh(geometry))
                    return
                }
            } catch {
                let description = (error as NSError)
                    .userInfo[NSLocalizedDescriptionKey] as? String ?? "\(error)"
                throw RuntimeErrorType.fileParsingError(
                    for: path, at: url, message: description
                )
            }
            throw RuntimeErrorType.fileTypeMismatch(
                for: path, at: url, expected: nil
            )
        }
        let oldURL = baseURL
        baseURL = url
        do {
            try program.evaluate(in: self)
            baseURL = oldURL
        } catch {
            baseURL = oldURL
            throw RuntimeErrorType.importError(ImportError(error), for: path, in: program.source)
        }
    }
}
