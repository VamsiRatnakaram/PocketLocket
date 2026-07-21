import Foundation
import SwiftData

/// Shared SwiftData container for the app's local cache.
enum AppModelContainer {
    static private(set) var persistentStoreError: String?

    static let shared: ModelContainer = {
        if isRunningTests {
            return makeInMemoryContainer()
        }

        do {
            return try ModelContainer(for: AccountRecord.self, TransactionRecord.self, CategoryRule.self)
        } catch {
            persistentStoreError = error.localizedDescription
            return makeInMemoryContainer()
        }
    }()

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let recoveryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: AccountRecord.self,
                TransactionRecord.self,
                CategoryRule.self,
                configurations: recoveryConfiguration
            )
        } catch {
            fatalError("Failed to create recovery SwiftData ModelContainer: \(error)")
        }
    }
}
