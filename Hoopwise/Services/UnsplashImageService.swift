import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct UnsplashImage: Codable {
    let id: String
    let urls: UnsplashURLs
    let user: UnsplashUser
    
    struct UnsplashURLs: Codable {
        let regular: String
        let small: String
    }
    
    struct UnsplashUser: Codable {
        let name: String
    }
}

class UnsplashImageService: ObservableObject {
    static let shared = UnsplashImageService()
    
    // MARK: - Properties
    private var accessKey: String { Self.apiKey }
    private let baseURL = "https://api.unsplash.com"
    #if canImport(UIKit)
    private let cache = NSCache<NSString, UIImage>()
    #elseif canImport(AppKit)
    private let cache = NSCache<NSString, NSImage>()
    #endif
    
    @Published var basketballImages: [UnsplashImage] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    // MARK: - Public Methods
    
    func fetchBasketballImages() {
        guard basketballImages.isEmpty else { return }
        
        isLoading = true
        let query = "basketball court game training"
        let url = URL(string: "\(baseURL)/search/photos?query=\(query)&per_page=20&orientation=landscape")!
        
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let response = try JSONDecoder().decode(SearchResponse.self, from: data)
                    self?.basketballImages = response.results
                } catch {
                    self?.error = error
                }
            }
        }.resume()
    }
    
    #if canImport(UIKit)
    typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    typealias PlatformImage = NSImage
    #endif

    func loadImage(from urlString: String) async -> PlatformImage? {
        if let cachedImage = cache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = PlatformImage(data: data) {
                cache.setObject(image, forKey: urlString as NSString)
                return image
            }
        } catch {
            debugLog("Error loading image: \(error)")
        }

        return nil
    }
}

// MARK: - Response Types

private struct SearchResponse: Codable {
    let results: [UnsplashImage]
}

// MARK: - SwiftUI Image View

struct UnsplashBackgroundImage: View {
    let urlString: String
    @State private var image: UnsplashImageService.PlatformImage?

    var body: some View {
        Group {
            if let image = image {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .task {
            image = await UnsplashImageService.shared.loadImage(from: urlString)
        }
    }
}
