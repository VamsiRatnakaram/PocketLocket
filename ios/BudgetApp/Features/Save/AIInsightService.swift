import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI insights via Apple's Foundation Models (iOS 26+). Runs entirely
/// on the device — no spending data ever leaves the phone. Falls back gracefully
/// when Apple Intelligence is unavailable (older devices, Simulator, etc.), in
/// which case the rules-based suggestions are shown on their own.
@Observable
@MainActor
final class AIInsightService {
    enum State: Equatable {
        case idle
        case loading
        case ready(String)
        case unavailable
    }

    var state: State = .idle

    @ObservationIgnored private var lastSignature: String?
    @ObservationIgnored private let textKey = "ai_insight_text"
    @ObservationIgnored private let signatureKey = "ai_insight_signature"

    /// Generates insights only when the input `signature` differs from the last
    /// run; otherwise reuses the cached text so we don't spend on-device compute.
    func generateIfNeeded(prompt: String, signature: String) async {
        if lastSignature == signature, case .ready = state { return }
        if let cached = cachedText(for: signature) {
            lastSignature = signature
            state = .ready(cached)
            return
        }
        await generate(prompt: prompt)
        persistIfReady(signature: signature)
    }

    /// Forces a fresh generation (manual refresh button).
    func regenerate(prompt: String, signature: String) async {
        await generate(prompt: prompt)
        persistIfReady(signature: signature)
    }

    private func persistIfReady(signature: String) {
        guard case let .ready(text) = state else { return }
        lastSignature = signature
        UserDefaults.standard.set(text, forKey: textKey)
        UserDefaults.standard.set(signature, forKey: signatureKey)
    }

    private func cachedText(for signature: String) -> String? {
        guard UserDefaults.standard.string(forKey: signatureKey) == signature else { return nil }
        return UserDefaults.standard.string(forKey: textKey)
    }

    private func generate(prompt: String) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                state = .unavailable
                return
            }
            state = .loading
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let response = try await session.respond(to: prompt)
                state = .ready(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                state = .unavailable
            }
            return
        }
        #endif
        state = .unavailable
    }

    private static let instructions = """
    You are a friendly, concise personal finance assistant. Based on the user's \
    monthly spending summary, give 2-3 short, specific, non-judgmental tips to save \
    money. Use plain language and a warm tone. Do not invent numbers that aren't \
    provided. Keep the whole response under 80 words.
    """
}
