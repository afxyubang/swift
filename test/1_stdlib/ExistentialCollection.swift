//===--- ExistentialCollection.swift --------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// RUN: %target-run-simple-swift

import StdlibUnittest

var tests = TestSuite("ExistentialCollection")

tests.test("AnyGenerator") {
  func countStrings() -> AnyGenerator<String> {
    let lazyStrings = lazy(0..<5).map { toString($0) }
    
    // This is a really complicated type of no interest to our
    // clients.
    let g: MapSequenceGenerator<RangeGenerator<Int>, String>
      = lazyStrings.generate()
    return anyGenerator(g)
  }
  expectEqual(["0", "1", "2", "3", "4"], Array(countStrings()))

  var x = 7
  let g = anyGenerator { x < 15 ? x++ : nil }
  expectEqual([ 7, 8, 9, 10, 11, 12, 13, 14 ], Array(g))
}

let initialCallCounts = [
  "successor": 0, "predecessor": 0,
  "preincrement": 0, "predecrement": 0,
  "postincrement": 0, "postdecrement": 0,
  "advancedBy": 0, "distanceTo": 0
]

var callCounts = initialCallCounts
  
struct InstrumentedIndex<I: RandomAccessIndexType> : RandomAccessIndexType {
  typealias Distance = I.Distance

  var base: I
  
  init(_ base: I) {
    self.base = base
  }
  
  static func resetCounts() {
    callCounts = initialCallCounts
  }
  
  func successor() -> InstrumentedIndex {
    ++callCounts["successor"]!
    return InstrumentedIndex(base.successor())
  }
  
  mutating func preincrement() {
    ++callCounts["preincrement"]!
    ++base
  }
  
  mutating func postincrement() {
    ++callCounts["postincrement"]!
    base++
  }
  
  func predecessor() -> InstrumentedIndex {
    ++callCounts["predecessor"]!
    return InstrumentedIndex(base.predecessor())
  }
  
  mutating func predecrement() {
    ++callCounts["predecrement"]!
    --base
  }
  
  mutating func postdecrement() {
    ++callCounts["postdecrement"]!
    base--
  }

  func advancedBy(distance: Distance) -> InstrumentedIndex {
    ++callCounts["advancedBy"]!
    return InstrumentedIndex(base.advancedBy(distance))
  }
  
  func distanceTo(other: InstrumentedIndex) -> Distance {
    ++callCounts["distanceTo"]!
    return base.distanceTo(other.base)
  }
}

prefix func ++ <I>(inout x: InstrumentedIndex<I>) -> InstrumentedIndex<I> {
  x.preincrement()
  return x
}

postfix func ++ <I>(inout x: InstrumentedIndex<I>) -> InstrumentedIndex<I> {
  let r = x
  x.postincrement()
  return r
}

prefix func -- <I>(inout x: InstrumentedIndex<I>) -> InstrumentedIndex<I> {
  x.predecrement()
  return x
}

postfix func -- <I>(inout x: InstrumentedIndex<I>) -> InstrumentedIndex<I> {
  let r = x
  x.postdecrement()
  return r
}

tests.test("Sequence") {
  let fib = [1, 2, 3, 5, 8, 13, 21]
  expectEqual(fib, Array(AnySequence(fib)))
  // AnyGenerator is a Sequence
  expectEqual(fib, Array(AnySequence(fib).generate()))
  expectCrashLater()
  let x = AnyGenerator<Int>()
}

tests.test("ForwardIndex") {
  var i = AnyForwardIndex(InstrumentedIndex(0))
  i = i.successor()
  expectEqual(1, callCounts["successor"])
  expectEqual(0, callCounts["preincrement"])
  expectEqual(0, callCounts["postincrement"])
  ++i
  expectEqual(1, callCounts["successor"])
  expectEqual(1, callCounts["preincrement"])
  expectEqual(0, callCounts["postincrement"])
  i++
  expectEqual(2, callCounts["successor"])
  expectEqual(1, callCounts["preincrement"])
  expectEqual(0, callCounts["postincrement"])
}

tests.test("BidirectionalIndex") {
  var i = AnyBidirectionalIndex(InstrumentedIndex(0))
  expectEqual(0, callCounts["predecessor"])
  expectEqual(0, callCounts["predecrement"])
  expectEqual(0, callCounts["postdecrement"])

  i = i.predecessor()
  expectEqual(1, callCounts["predecessor"])
  expectEqual(0, callCounts["predecrement"])
  expectEqual(0, callCounts["postdecrement"])
  --i
  expectEqual(1, callCounts["predecessor"])
  expectEqual(1, callCounts["predecrement"])
  expectEqual(0, callCounts["postdecrement"])
  i--
  expectEqual(2, callCounts["predecessor"])
  expectEqual(1, callCounts["predecrement"])
  expectEqual(0, callCounts["postdecrement"])
}

tests.test("ForwardCollection") {
  let a0: ContiguousArray = [1, 2, 3, 5, 8, 13, 21]
  let fc0 = AnyForwardCollection(a0)
  let a1 = ContiguousArray(fc0)
  expectEqual(a0, a1)
  for e in a0 {
    let i = find(fc0, e)
    expectNotEmpty(i)
    expectEqual(e, fc0[i!])
  }
  for i in indices(fc0) {
    expectNotEqual(fc0.endIndex, i)
    expectEqual(1, count(filter(indices(fc0)) {$0 == i}))
  }
}

tests.test("BidirectionalCollection") {
  let a0: ContiguousArray = [1, 2, 3, 5, 8, 13, 21]
  let fc0 = AnyForwardCollection(lazy(a0).reverse())
  
  let bc0_ = AnyBidirectionalCollection(fc0)         // upgrade!
  expectNotEmpty(bc0_)
  let bc0 = bc0_!
  expectTrue(fc0 === bc0)

  let fc1 = AnyForwardCollection(lazy(a0).reverse()) // new collection
  expectFalse(fc1 === fc0)

  let fc2 = AnyForwardCollection(bc0)                // downgrade
  expectTrue(fc2 === bc0)
  
  let a1 = ContiguousArray(lazy(bc0).reverse())
  expectEqual(a0, a1)
  for e in a0 {
    let i = find(bc0, e)
    expectNotEmpty(i)
    expectEqual(e, bc0[i!])
  }
  for i in indices(bc0) {
    expectNotEqual(bc0.endIndex, i)
    expectEqual(1, count(filter(indices(bc0)) {$0 == i}))
  }
  
  // Can't upgrade a non-random-access collection to random access
  let s0 = "Hello, Woyld"
  let bc1 = AnyBidirectionalCollection(s0)
  let fc3 = AnyForwardCollection(bc1)
  expectTrue(fc3 === bc1)
  expectEmpty(AnyRandomAccessCollection(bc1))
  expectEmpty(AnyRandomAccessCollection(fc3))
}

tests.test("RandomAccessCollection") {
  let a0: ContiguousArray = [1, 2, 3, 5, 8, 13, 21]
  let fc0 = AnyForwardCollection(lazy(a0).reverse())
  let rc0_ = AnyRandomAccessCollection(fc0)         // upgrade!
  expectNotEmpty(rc0_)
  let rc0 = rc0_!
  expectTrue(rc0 === fc0)

  let bc1 = AnyBidirectionalCollection(rc0)         // downgrade
  expectTrue(bc1 === rc0)

  let fc1 = AnyBidirectionalCollection(rc0)         // downgrade
  expectTrue(fc1 === rc0)
  
  let a1 = ContiguousArray(lazy(rc0).reverse())
  expectEqual(a0, a1)
  for e in a0 {
    let i = find(rc0, e)
    expectNotEmpty(i)
    expectEqual(e, rc0[i!])
  }
  for i in indices(rc0) {
    expectNotEqual(rc0.endIndex, i)
    expectEqual(1, count(filter(indices(rc0)) {$0 == i}))
  }
}

runAllTests()
