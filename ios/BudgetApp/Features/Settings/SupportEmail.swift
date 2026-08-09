import Foundation

enum SupportEmail {
    static let recipient = "vamsiratnakaram@gmail.com"

    static func url(version: String, build: String, operatingSystem: String) -> URL? {
        let body = """
        Hello,

        Please describe what happened:


        What were you trying to do?


        What did you expect to happen?


        App version: \(version) (\(build))
        iOS: \(operatingSystem)

        Please do not include passwords, bank credentials, SimpleFIN setup tokens, account numbers, or full transaction details.
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PocketLocket Support Request"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}