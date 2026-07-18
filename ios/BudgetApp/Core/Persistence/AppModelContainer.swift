import Foundation
import SwiftData

/// Shared SwiftData container for the app's local cache.
enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: AccountRecord.self, TransactionRecord.self, CategoryRule.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()
}
