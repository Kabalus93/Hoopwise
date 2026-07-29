import SwiftUI

/// A reusable view for displaying student names with language-aware formatting
/// In Chinese mode: Shows Chinese name prominently with English name smaller below
/// In English mode: Shows English name only
struct StudentNameView: View {
    let student: Student
    var primaryFont: Font = .system(size: 16, weight: .semibold)
    var secondaryFont: Font = .system(size: 12)
    var primaryColor: Color = AppTheme.textPrimary
    var secondaryColor: Color = .secondary
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var body: some View {
        if isChinese && student.chineseName != nil {
            // Chinese mode with Chinese name available
            VStack(alignment: alignment, spacing: spacing) {
                Text(student.chineseName!)
                    .font(primaryFont)
                    .foregroundColor(primaryColor)
                    .lineLimit(1)
                
                Text(student.name)
                    .font(secondaryFont)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
        } else {
            // English mode or no Chinese name
            Text(student.name)
                .font(primaryFont)
                .foregroundColor(primaryColor)
                .lineLimit(1)
        }
    }
}

/// Compact version for inline use (single line)
struct StudentNameInline: View {
    let student: Student
    var font: Font = .system(size: 14, weight: .medium)
    var color: Color = AppTheme.textPrimary
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var body: some View {
        Text(student.displayName)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
    }
}

/// Card-style name view with more prominent styling
struct StudentNameCard: View {
    let student: Student
    var showSecondaryName: Bool = true
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    var body: some View {
        if isChinese && student.chineseName != nil && showSecondaryName {
            VStack(alignment: .leading, spacing: 2) {
                Text(student.chineseName!)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(student.name)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(student.displayName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(alignment: .leading, spacing: 20) {
        Text("English Mode").font(.headline)
        StudentNameView(student: Student.samples[0])
        StudentNameInline(student: Student.samples[0])
        StudentNameCard(student: Student.samples[0])
        
        Divider()
        
        Text("Chinese Mode (simulated)").font(.headline)
        // Note: In preview, language is English by default
        // These would show Chinese names in Chinese mode
        StudentNameView(student: Student.samples[0])
        StudentNameInline(student: Student.samples[0])
        StudentNameCard(student: Student.samples[0])
    }
    .padding()
}
