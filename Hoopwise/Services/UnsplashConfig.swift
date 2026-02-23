import Foundation

extension UnsplashImageService {
    /// Get your API key from https://unsplash.com/developers
    static var apiKey: String {
        // For development, you can hardcode your API key here
        // For production, you should move this to a secure location or use environment variables
        #if DEBUG
        return "YOUR_UNSPLASH_ACCESS_KEY"
        #else
        guard let key = Bundle.main.object(forInfoDictionaryKey: "UnsplashAccessKey") as? String else {
            fatalError("Unsplash API key not found in Info.plist")
        }
        return key
        #endif
    }
}
