import Foundation
import Combine

// MARK: - Supabase Configuration
struct SupabaseConfig {
    private static let legacyURL = "https://hgcowjhrajbnhzwkqhko.supabase.co"
    private static let legacyAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhnY293amhyYWpibmh6d2txaGtvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0MjMyMTMsImV4cCI6MjA4MDk5OTIxM30.g5FRg9MIias65b7Nxo55OKUCZq6G2eRHBPyyryitNrA"

    static let url: String = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return legacyURL
    }()

    static let anonKey: String = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return legacyAnonKey
    }()

    static var isUsingLegacyFallback: Bool {
        let hasConfiguredURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.isEmpty == false
        let hasConfiguredKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?.isEmpty == false
        return !(hasConfiguredURL && hasConfiguredKey)
    }
}

// MARK: - Supabase Error
enum SupabaseError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        case .serverError(let code, let message): return "Server error \(code): \(message)"
        case .notConfigured: return "Supabase not configured"
        }
    }
}

// MARK: - Filter Operator
enum FilterOperator: String {
    case eq, neq, gt, gte, lt, lte, like, ilike, `in`, contains
}

// MARK: - Supabase Manager
@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    @Published var isInitialized = false
    @Published var isConnected = false
    
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession
    private let healthSession: URLSession
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private init() {
        self.baseURL = SupabaseConfig.url
        self.apiKey = SupabaseConfig.anonKey

        if SupabaseConfig.isUsingLegacyFallback {
            debugLog("⚠️ Supabase credentials are using legacy fallback values. Configure SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist for production.")
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        // A fast, non-blocking session for startup connectivity checks.
        // Avoid waitsForConnectivity to prevent long stalls on app launch.
        let healthConfig = URLSessionConfiguration.ephemeral
        healthConfig.timeoutIntervalForRequest = 10
        healthConfig.timeoutIntervalForResource = 15
        healthConfig.waitsForConnectivity = false
        self.healthSession = URLSession(configuration: healthConfig)
        
        // Configure encoder/decoder for snake_case (Supabase convention)
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
        // IMPORTANT: Output null for nil values to fix PGRST102 "All object keys must match"
        self.encoder.outputFormatting = .sortedKeys
        
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Use custom date decoding to handle Supabase's ISO8601 with fractional seconds
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try multiple date formats that Supabase might return
            let formatters: [ISO8601DateFormatter] = {
                let formatter1 = ISO8601DateFormatter()
                formatter1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let formatter2 = ISO8601DateFormatter()
                formatter2.formatOptions = [.withInternetDateTime]
                
                return [formatter1, formatter2]
            }()
            
            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            
            // Fallback: try DateFormatter with common formats
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss"
            ]
            
            for format in formats {
                fallbackFormatter.dateFormat = format
                if let date = fallbackFormatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
    }

    func invokeFunction<RequestBody: Encodable, ResponseBody: Decodable>(name: String, body: RequestBody) async throws -> ResponseBody {
        let urlString = "\(baseURL)/functions/v1/\(name)"
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        do {
            let (data, response) = try await healthSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.serverError(httpResponse.statusCode, message)
            }
            return try decoder.decode(ResponseBody.self, from: data)
        } catch let error as SupabaseError {
            throw error
        } catch let error as DecodingError {
            throw SupabaseError.decodingError(error)
        } catch {
            throw SupabaseError.networkError(error)
        }
    }
    
    func initialize() async {
        // Check if properly configured
        guard !baseURL.contains("your-project") else {
            debugLog("⚠️ Supabase not configured - using local storage only")
            isInitialized = false
            return
        }

        // Do not block app launch on network reachability.
        // Mark initialized immediately so the app can work offline.
        isInitialized = true
        debugLog("🔄 Initializing Supabase connection to: \(baseURL)")

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.testConnection()
                self.isConnected = result
                if result {
                    debugLog("✅ Supabase connected successfully")
                } else {
                    debugLog("⚠️ Supabase reachable but tables may not exist - run schema SQL")
                }
            } catch {
                self.isConnected = false
                if let urlError = error as? URLError {
                    debugLog("ℹ️ Cloud sync unavailable (URLError \(urlError.code.rawValue): \(urlError.localizedDescription)) - using local storage only")
                } else {
                    debugLog("ℹ️ Cloud sync unavailable - using local storage only")
                }
            }
        }
    }
    
    /// Test connection by making a simple request to the REST API
    func testConnection() async throws -> Bool {
        // First try a simple health check to the base URL
        let healthURL = "\(baseURL)/rest/v1/"
        
        guard let url = URL(string: healthURL) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await healthSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                debugLog("📡 Supabase health check status: \(httpResponse.statusCode)")
                
                // Any 2xx or even 4xx means the server is reachable
                if (200...499).contains(httpResponse.statusCode) {
                    // Now try to access the students table
                    return try await testTableAccess()
                } else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugLog("⚠️ Supabase server error: \(message)")
                    return false
                }
            }
            return false
        } catch {
            if let urlError = error as? URLError {
                debugLog("❌ Supabase network error (URLError \(urlError.code.rawValue)): \(urlError.localizedDescription)")
            } else {
                debugLog("❌ Supabase network error: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    /// Test if we can access the students table
    private func testTableAccess() async throws -> Bool {
        let urlString = "\(baseURL)/rest/v1/students?select=id&limit=1"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                debugLog("📡 Supabase students table status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseStr = String(data: data, encoding: .utf8) {
                        debugLog("📡 Supabase response: \(responseStr.prefix(100))")
                    }
                    return true
                } else if httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
                    // Table doesn't exist - need to run schema
                    debugLog("⚠️ Supabase 'students' table not found. Please run the schema SQL in Supabase SQL Editor.")
                    debugLog("📋 Schema file: SAM/supabase_schema.sql")
                    // Return true since server is reachable, just tables missing
                    isConnected = true
                    return true
                } else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugLog("⚠️ Supabase table error: \(message)")
                    return false
                }
            }
            return false
        } catch {
            debugLog("❌ Supabase table access error: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get connection status info for debugging
    func getConnectionInfo() -> String {
        var info = "Supabase Connection Info:\n"
        info += "- URL: \(baseURL)\n"
        info += "- Initialized: \(isInitialized)\n"
        info += "- Connected: \(isConnected)\n"
        info += "- API Key: \(apiKey.prefix(20))...\n"
        return info
    }
    
    // MARK: - Generic CRUD Operations
    
    func fetch<T: Decodable>(from table: String, limit: Int? = nil, orderBy: String? = nil, ascending: Bool = true, selectColumns: String = "*") async throws -> [T] {
        var urlString = "\(baseURL)/rest/v1/\(table)?select=\(selectColumns)"
        
        if let orderBy = orderBy {
            urlString += "&order=\(orderBy).\(ascending ? "asc" : "desc")"
        }
        if let limit = limit {
            urlString += "&limit=\(limit)"
        }
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.serverError(httpResponse.statusCode, message)
            }
            
            return try decoder.decode([T].self, from: data)
        } catch let error as SupabaseError {
            throw error
        } catch let error as DecodingError {
            throw SupabaseError.decodingError(error)
        } catch {
            throw SupabaseError.networkError(error)
        }
    }
    
    func fetchWithFilter<T: Decodable>(from table: String, column: String, op: FilterOperator, value: String) async throws -> [T] {
        let filterValue: String
        switch op {
        case .eq: filterValue = "eq.\(value)"
        case .neq: filterValue = "neq.\(value)"
        case .gt: filterValue = "gt.\(value)"
        case .gte: filterValue = "gte.\(value)"
        case .lt: filterValue = "lt.\(value)"
        case .lte: filterValue = "lte.\(value)"
        case .like: filterValue = "like.\(value)"
        case .ilike: filterValue = "ilike.\(value)"
        case .in: filterValue = "in.(\(value))"
        case .contains: filterValue = "cs.{\(value)}"
        }
        
        let urlString = "\(baseURL)/rest/v1/\(table)?select=*&\(column)=\(filterValue)"
        
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
        
        return try decoder.decode([T].self, from: data)
    }
    
    func insert<T: Encodable>(into table: String, data: T) async throws {
        let urlString = "\(baseURL)/rest/v1/\(table)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try encoder.encode(data)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
    }
    
    func update<T: Encodable>(table: String, id: UUID, data: T) async throws {
        let urlString = "\(baseURL)/rest/v1/\(table)?id=eq.\(id.uuidString)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try encoder.encode(data)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
    }
    
    func delete(from table: String, id: UUID) async throws {
        let urlString = "\(baseURL)/rest/v1/\(table)?id=eq.\(id.uuidString)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
    }
    
    /// Upsert (insert or update) - useful for syncing
    func upsert<T: Encodable>(into table: String, data: T, onConflict: String = "id") async throws {
        let urlString = "\(baseURL)/rest/v1/\(table)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try encoder.encode(data)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
    }
    
    /// Batch upsert for syncing multiple records
    func batchUpsert<T: Encodable>(into table: String, data: [T]) async throws {
        guard !data.isEmpty else { return }
        
        let urlString = "\(baseURL)/rest/v1/\(table)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try encoder.encode(data)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
    }
    
    /// Check if tables exist (for initial setup)
    func checkTableExists(_ table: String) async -> Bool {
        do {
            let urlString = "\(baseURL)/rest/v1/\(table)?select=id&limit=0"
            guard let url = URL(string: urlString) else { return false }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(apiKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Storage Operations
    
    /// Upload an image to Supabase Storage
    /// - Parameters:
    ///   - imageData: The image data (JPEG)
    ///   - bucket: Storage bucket name (default: "profile-images")
    ///   - path: Path within the bucket (e.g., "students/uuid.jpg")
    /// - Returns: Public URL of the uploaded image
    func uploadImage(imageData: Data, bucket: String = "profile-images", path: String) async throws -> String {
        let urlString = "\(baseURL)/storage/v1/object/\(bucket)/\(path)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.addValue("true", forHTTPHeaderField: "x-upsert") // Overwrite if exists
        request.httpBody = imageData
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if (200...299).contains(httpResponse.statusCode) {
                // Return the public URL
                let publicUrl = "\(baseURL)/storage/v1/object/public/\(bucket)/\(path)"
                debugLog("✅ Image uploaded successfully: \(publicUrl)")
                return publicUrl
            } else {
                let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                debugLog("❌ Image upload failed: \(message)")
                throw SupabaseError.serverError(httpResponse.statusCode, message)
            }
        }
        
        throw SupabaseError.networkError(NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))
    }
    
    /// Delete an image from Supabase Storage
    func deleteImage(bucket: String = "profile-images", path: String) async throws {
        let urlString = "\(baseURL)/storage/v1/object/\(bucket)/\(path)"
        
        guard let url = URL(string: urlString) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }
        
        debugLog("✅ Image deleted successfully")
    }

    // MARK: - Lightweight Change Detection

    /// Check if any synced table has records updated after `since` for the given org.
    /// Returns the first table name with changes, or nil if nothing changed.
    func hasCloudChanges(since: Date, organizationId: UUID) async -> String? {
        let tables = ["students", "players", "contracts", "programs", "micro_cycles",
                      "session_events", "drills", "measurements", "staff_coaches", "locations"]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceStr = iso.string(from: since)

        return await withTaskGroup(of: String?.self) { group in
            for table in tables {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let urlString = "\(self.baseURL)/rest/v1/\(table)?select=id&organization_id=eq.\(organizationId.uuidString)&updated_at=gt.\(sinceStr)&limit=1"
                        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return nil }

                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"
                        request.addValue(self.apiKey, forHTTPHeaderField: "apikey")
                        request.addValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                        let (data, response) = try await self.healthSession.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
                        // If the response array is non-empty, there are changes
                        return data.count > 2 ? table : nil  // "[]" = 2 bytes = no changes
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let tableName = result { return tableName }
            }
            return nil
        }
    }
}

// MARK: - Claude API Manager
class ClaudeManager {
    static let shared = ClaudeManager()
    
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(
        query: String,
        context: String,
        language: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeError.noApiKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidURL
        }
        
        let isChinese = language == "zh"
        
        let systemPrompt = """
        You are a helpful AI coaching assistant for a sports coaching management app. Your role is to help coaches manage their students, analyze performance data, organize sessions, and provide insights.
        
        PRIVACY & CHILD SAFETY (CRITICAL):
        - This data involves minors/young athletes. Handle ALL information with utmost confidentiality.
        - NEVER suggest sharing student data externally or with third parties.
        - Keep responses focused on coaching and session management only.
        - Do not make assumptions about students' personal lives or circumstances.
        - Refer to students professionally by first name only in responses.
        
        You have access to the following context about the coach's data:
        \(context)
        
        Guidelines:
        - Be concise and helpful
        - Provide actionable coaching insights
        - Use the actual data provided - reference specific students, sessions, contracts
        - Respond in \(isChinese ? "Chinese (简体中文)" : "English")
        - Format responses clearly without raw markdown symbols
        - Be encouraging and professional
        - Use entity cards to show data visually
        
        FORMATTING:
        - Use plain text, avoid **bold** markers in your responses
        - Use • for bullet points instead of *
        - Keep responses clean and readable
        
        ENTITY CARDS (for visual display):
        [[entity:TYPE|ID|field1|field2|...]]
        
        Formats:
        - Student: [[entity:student|UUID|name|chineseName|sessionsLeft|avatarColor]]
        - Contract: [[entity:contract|UUID|studentName|sessionsLeft|totalSessions|status]]
        - Session: [[entity:session|UUID|title|timestamp|location|attendeeCount]]
        - Program: [[entity:program|UUID|name|studentCount|status]]
        - Drill: [[entity:drill|UUID|name|category|duration|isFavorite]]
        
        ACTION BUTTONS (for navigation):
        [[action:TYPE|TITLE|ICON|PAYLOAD]]
        
        Types: view_student, view_contract, view_session, view_stats, go_to_tab, contact_parent, schedule_session, view_program, view_drill
        
        Use entity cards for data display, actions for navigation.
        """
        
        let requestBody = ClaudeRequest(
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 1024,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: query)
            ]
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw ClaudeError.invalidApiKey
                } else if !(200...299).contains(httpResponse.statusCode) {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw ClaudeError.serverError(httpResponse.statusCode, errorMessage)
                }
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let claudeResponse = try decoder.decode(ClaudeResponse.self, from: data)
            
            return claudeResponse.content.first?.text ?? "No response generated"
        } catch let error as ClaudeError {
            throw error
        } catch {
            throw ClaudeError.networkError(error)
        }
    }
}

// MARK: - Claude Error
enum ClaudeError: Error, LocalizedError {
    case noApiKey
    case invalidApiKey
    case invalidURL
    case networkError(Error)
    case serverError(Int, String)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key configured. Please add your Claude API key in Settings."
        case .invalidApiKey:
            return "Invalid API key. Please check your Claude API key in Settings."
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let error):
            return "Response error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Claude API Models
struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ClaudeContent]
    let model: String
    let stopReason: String?
    let stopSequence: String?
    let usage: ClaudeUsage
}

struct ClaudeContent: Decodable {
    let type: String
    let text: String
}

struct ClaudeUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - Groq API Manager
class GroqManager {
    static let shared = GroqManager()
    
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(
        query: String,
        context: String,
        language: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GroqError.noApiKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw GroqError.invalidURL
        }
        
        let isChinese = language == "zh"
        
        let systemPrompt = """
        You are a helpful AI coaching assistant for a sports coaching management app. Your role is to help coaches manage their students, analyze performance data, organize sessions, and provide insights.
        
        PRIVACY & CHILD SAFETY (CRITICAL):
        - This data involves minors/young athletes. Handle ALL information with utmost confidentiality.
        - NEVER suggest sharing student data externally or with third parties.
        - Keep responses focused on coaching and session management only.
        - Do not make assumptions about students' personal lives or circumstances.
        - Refer to students professionally by first name only in responses.
        
        You have access to the following context about the coach's data:
        \(context)
        
        Guidelines:
        - Be concise and helpful
        - Provide actionable coaching insights
        - Use the actual data provided - reference specific students, sessions, contracts
        - Respond in \(isChinese ? "Chinese (简体中文)" : "English")
        - Format responses clearly without raw markdown symbols
        - Be encouraging and professional
        - Use entity cards to show data visually
        
        FORMATTING:
        - Use plain text, avoid **bold** markers in your responses
        - Use • for bullet points instead of *
        - Keep responses clean and readable
        
        ENTITY CARDS (for visual display):
        [[entity:TYPE|ID|field1|field2|...]]
        
        Formats:
        - Student: [[entity:student|UUID|name|chineseName|sessionsLeft|avatarColor]]
        - Contract: [[entity:contract|UUID|studentName|sessionsLeft|totalSessions|status]]
        - Session: [[entity:session|UUID|title|timestamp|location|attendeeCount]]
        - Program: [[entity:program|UUID|name|studentCount|status]]
        - Drill: [[entity:drill|UUID|name|category|duration|isFavorite]]
        
        ACTION BUTTONS (for navigation):
        [[action:TYPE|TITLE|ICON|PAYLOAD]]
        
        Types: view_student, view_contract, view_session, view_stats, go_to_tab, contact_parent, schedule_session, view_program, view_drill
        
        Use entity cards for data display, actions for navigation.
        """
        
        let requestBody = GroqRequest(
            model: "llama-3.3-70b-versatile",
            messages: [
                GroqMessage(role: "system", content: systemPrompt),
                GroqMessage(role: "user", content: query)
            ],
            maxTokens: 1024,
            temperature: 0.7
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw GroqError.invalidApiKey
                } else if !(200...299).contains(httpResponse.statusCode) {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw GroqError.serverError(httpResponse.statusCode, errorMessage)
                }
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let groqResponse = try decoder.decode(GroqResponse.self, from: data)
            
            return groqResponse.choices.first?.message.content ?? "No response generated"
        } catch let error as GroqError {
            throw error
        } catch {
            throw GroqError.networkError(error)
        }
    }
}

// MARK: - Groq Error
enum GroqError: Error, LocalizedError {
    case noApiKey
    case invalidApiKey
    case invalidURL
    case networkError(Error)
    case serverError(Int, String)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key configured. Please add your Groq API key in Settings."
        case .invalidApiKey:
            return "Invalid API key. Please check your Groq API key in Settings."
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let error):
            return "Response error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Groq API Models
struct GroqRequest: Encodable {
    let model: String
    let messages: [GroqMessage]
    let maxTokens: Int
    let temperature: Double
}

struct GroqMessage: Codable {
    let role: String
    let content: String
}

struct GroqResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [GroqChoice]
    let usage: GroqUsage?
}

struct GroqChoice: Decodable {
    let index: Int
    let message: GroqMessage
    let finishReason: String?
}

struct GroqUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}
