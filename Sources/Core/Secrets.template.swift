// Copy this file to Secrets.swift and fill in your values.
// Secrets.swift is gitignored and should never be committed.
enum Secrets {
    /// BFF proxy server URL (e.g. "https://api.yourdomain.com/v1/chat/completions")
    static let baseURL = "https://api.smallbeebee.com/v1/chat/completions"

    /// Shared secret for authenticating with the BFF proxy
    static let appToken = "<YOUR_APP_TOKEN>"
}
