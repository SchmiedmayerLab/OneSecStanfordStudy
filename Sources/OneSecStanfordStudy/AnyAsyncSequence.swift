//
// This source file is part of the OneSecStanfordStudy open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

// MARK: AnyAsyncSequence

/// A type-erased wrapper over an `AsyncSequence`.
public struct AnyAsyncSequence<Element, Failure: Error>: AsyncSequence {
    @usableFromInline let makeIterator: () -> AnyAsyncIterator<Element, Failure>

    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence`
    @available(iOS 18.0, *)
    @inlinable
    public init(_ base: some AsyncSequence<Element, Failure>) {
        makeIterator = {
            AnyAsyncIterator(base.makeAsyncIterator())
        }
    }

    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence`
    @_disfavoredOverload
    @inlinable
    public init<S: AsyncSequence>(_ base: S) where S.Element == Element, Failure == any Error {
        makeIterator = {
            AnyAsyncIterator(base.makeAsyncIterator())
        }
    }

    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence` and assumes it will never throw.
    ///
    /// This initializer will forcibly coerce the input sequence into one of a type whose `Failure` is `Never`.
    /// If the sequence does in fact end up throwing an error, that is a programmer error and will result in the program getting terminated.
    ///
    /// Use this initializer in pre-iOS 18 situations, where `AsyncSequence`'s `Failure` type isn't yet available.
    @inlinable
    public init<S: AsyncSequence>(unsafelyAssumingDoesntThrow base: S) where S.Element == Element, Failure == Never {
        makeIterator = {
            AnyAsyncIterator(unsafelyAssumingDoesntThrow: base.makeAsyncIterator())
        }
    }

    @inlinable
    public func makeAsyncIterator() -> AnyAsyncIterator<Element, Failure> {
        makeIterator()
    }
}

// MARK: AnyAsyncIterator

/// A type-erased async iterator.
public struct AnyAsyncIterator<Element, Failure: Error>: AsyncIteratorProtocol {
    @usableFromInline var base: any AsyncIteratorProtocol

    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base iterator's `Element` and `Failure` types.
    @available(iOS 18, *)
    @inlinable
    public init(_ base: some AsyncIteratorProtocol<Element, Failure>) {
        self.base = base
    }

    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base iterator's `Element` type.
    @_disfavoredOverload
    @inlinable
    public init<I: AsyncIteratorProtocol>(_ base: I) where I.Element == Element, Failure == any Error {
        self.base = base
    }

    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base
    /// iterator's `Element` type, and assumes it will never throw.
    ///
    /// This initializer will forcibly coerce the input sequence into one of a type whose `Failure` is `Never`.
    /// If the sequence does in fact end up throwing an error, that is a programmer error and will result in the program getting terminated.
    ///
    /// Use this initializer in pre-iOS 18 situations, where `AsyncSequence`'s `Failure` type isn't yet available.
    @inlinable
    public init<I: AsyncIteratorProtocol>(unsafelyAssumingDoesntThrow base: I) where I.Element == Element, Failure == Never {
        self.base = base
    }

    @inlinable
    public mutating func next() async throws -> Element? {
        try await base.next() as? Element
    }

    @available(iOS 18.0, *)
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        do {
            return try await base.next(isolation: actor) as? Element
        } catch {
            // SAFETY: our initializers only allow creating `AnyAsyncIterator`s with a matching `Failure` type
            throw error as! Failure // swiftlint:disable:this force_cast
        }
    }
}
