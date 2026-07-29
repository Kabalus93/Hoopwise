import Foundation

// MARK: - Pinyin Converter
/// Utility for converting Chinese characters to Pinyin
/// Uses iOS/macOS built-in CFStringTransform for accurate conversion
struct PinyinConverter {
    
    // MARK: - Migration: Add Tone Marks to Existing Students
    
    /// Checks if a student's name should be migrated to toned pinyin.
    /// Returns the new toned name if migration is needed, nil otherwise.
    /// Only returns a value if:
    /// 1. Student has a chineseName set
    /// 2. The current name exactly matches the plain pinyin of that chineseName
    /// This ensures manually-entered English names are NOT modified.
    static func tonedPinyinIfNeeded(name: String, chineseName: String?) -> String? {
        guard let chineseName = chineseName, !chineseName.isEmpty else {
            return nil
        }
        
        let currentName = name.trimmingCharacters(in: .whitespaces)
        let plainPinyin = toPinyinPlain(chineseName).trimmingCharacters(in: .whitespaces)
        
        // Only migrate if current name exactly matches the plain pinyin (case-insensitive)
        guard currentName.lowercased() == plainPinyin.lowercased() else {
            return nil
        }
        
        let tonedPinyin = toPinyin(chineseName)
        
        // Only return if different (avoids unnecessary writes)
        return tonedPinyin != currentName ? tonedPinyin : nil
    }
    
    /// Convert Chinese text to Pinyin with tone marks preserved (e.g., 张 → Zhāng)
    /// - Parameter chinese: Chinese text to convert
    /// - Returns: Pinyin representation with tone marks, spaces between syllables, capitalized for names
    static func toPinyin(_ chinese: String) -> String {
        guard !chinese.isEmpty else { return "" }
        
        let mutableString = NSMutableString(string: chinese) as CFMutableString
        
        // Convert to Pinyin with tone marks (preserving diacritics for pronunciation help)
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        
        // Note: We intentionally do NOT strip diacritics to help coaches pronounce names correctly
        // e.g., 张 → Zhāng (tone 1), 王 → Wáng (tone 2)
        
        // Convert to proper name capitalization while preserving tone marks
        let pinyin = (mutableString as String)
            .components(separatedBy: " ")
            .map { word in
                guard let first = word.first else { return word }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
        
        return pinyin
    }
    
    /// Convert Chinese text to Pinyin without tone marks (plain ASCII)
    /// - Parameter chinese: Chinese text to convert
    /// - Returns: Pinyin representation without tone marks
    static func toPinyinPlain(_ chinese: String) -> String {
        guard !chinese.isEmpty else { return "" }
        
        let mutableString = NSMutableString(string: chinese) as CFMutableString
        
        // Convert to Pinyin with tone marks
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        
        // Remove tone marks (diacritics)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        
        // Convert to proper name capitalization
        let pinyin = (mutableString as String)
            .components(separatedBy: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        
        return pinyin
    }
    
    /// Check if a string contains Chinese characters
    /// - Parameter text: Text to check
    /// - Returns: true if the text contains Chinese characters
    static func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs range
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||  // CJK Extension A
               (0x20000...0x2A6DF).contains(scalar.value) { // CJK Extension B
                return true
            }
        }
        return false
    }
    
    /// Check if text is purely Chinese (no Latin letters)
    /// - Parameter text: Text to check
    /// - Returns: true if the text contains only Chinese characters and spaces/punctuation
    static func isPurelyChinese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        for scalar in trimmed.unicodeScalars {
            let value = scalar.value
            // Allow Chinese characters
            let isChinese = (0x4E00...0x9FFF).contains(value) ||
                           (0x3400...0x4DBF).contains(value) ||
                           (0x20000...0x2A6DF).contains(value)
            // Allow spaces and common punctuation
            let isAllowed = CharacterSet.whitespaces.contains(scalar) ||
                           CharacterSet.punctuationCharacters.contains(scalar)
            
            if !isChinese && !isAllowed {
                return false
            }
        }
        return true
    }
}
