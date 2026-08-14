import XCTest
@testable import PocketLocket

final class DerivedCacheTests: XCTestCase {
    func testBuildRunsOnceForRepeatedReadsOfTheSameKey() {
        let cache = DerivedCache<Int, String>()
        var builds = 0
        for _ in 0..<5 {
            _ = cache.value(for: 1) {
                builds += 1
                return "a"
            }
        }
        XCTAssertEqual(builds, 1, "The whole point: six reads per body must not be six computations")
    }

    func testKeyChangeRebuilds() {
        let cache = DerivedCache<Int, String>()
        var builds = 0
        let build: () -> String = { builds += 1; return "\(builds)" }

        XCTAssertEqual(cache.value(for: 1, build: build), "1")
        XCTAssertEqual(cache.value(for: 2, build: build), "2")
        XCTAssertEqual(cache.value(for: 2, build: build), "2")
        XCTAssertEqual(builds, 2)
    }

    /// A cache that only ever grows forward would serve stale data when a user
    /// toggles a filter off and back on, so returning to a previous key must
    /// still recompute rather than resurrect an older entry.
    func testReturningToAPreviousKeyRebuilds() {
        let cache = DerivedCache<Int, Int>()
        var builds = 0
        let build: () -> Int = { builds += 1; return builds }

        _ = cache.value(for: 1, build: build)
        _ = cache.value(for: 2, build: build)
        _ = cache.value(for: 1, build: build)
        XCTAssertEqual(builds, 3)
    }
}
