import Foundation

/// Memoizes an expensive derivation across SwiftUI body evaluations.
///
/// SwiftUI does not memoize computed properties. A `private var rows: [Row] {
/// transactions.filter { ... }.sorted { ... } }` re-runs *in full* at every
/// single reference, and a realistic `body` references its derived list several
/// times over: once in the `ForEach`, again for a `.disabled(rows.isEmpty)`
/// toolbar button, again for a count in a header, again in an `isEmpty`
/// content-unavailable overlay. Each of those looks free at the call site and
/// costs another O(n log n) pass over the whole table.
///
/// Hold one of these in `@State` and route the derivation through it. It is a
/// plain reference type — deliberately *not* `Observable` — so writing to it
/// while producing a body cannot invalidate the view and cause a render loop.
///
/// The key must capture everything the derivation reads. For SwiftData-backed
/// lists that means a content hash of the records, not just their count: edits
/// that recategorize a transaction leave the count untouched, and a key that
/// missed them would serve a stale list forever.
final class DerivedCache<Key: Equatable, Value> {
    private var key: Key?
    private var cached: Value?

    init() {}

    /// Returns the memoized value for `key`, invoking `build` only when the key
    /// differs from the one that produced the current value.
    func value(for key: Key, build: () -> Value) -> Value {
        if let cached, self.key == key { return cached }
        let fresh = build()
        self.key = key
        self.cached = fresh
        return fresh
    }
}
