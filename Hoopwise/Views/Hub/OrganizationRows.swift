import SwiftUI

// The Organization page's rows (November 2026 redesign): the app's list
// manner — a 40 pt avatar or tinted icon tile, the name at body size, one
// secondary line, a chevron — instead of the card per row each tab had.

/// A rounded, tinted symbol tile like the ones in Settings.
struct OrgIconTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

private struct OrgChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

private struct OrgInactiveTag: View {
    var body: some View {
        Text(LocalizationManager.shared.currentLanguage == .chinese ? "停用" : "Inactive")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: .capsule)
    }
}

extension CoachRole {
    var localizedName: String {
        guard LocalizationManager.shared.currentLanguage == .chinese else { return rawValue }
        switch self {
        case .head: return "主教练"
        case .assistant: return "助理教练"
        case .volunteer: return "志愿者"
        case .trainee: return "实习教练"
        }
    }
}

// MARK: - Coach

struct OrgCoachRow: View {
    let coach: StaffCoach
    @EnvironmentObject var dataManager: DataManager

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var isYou: Bool { coach.id == dataManager.loggedInCoachId }
    private var programCount: Int { dataManager.programs.filter { $0.coachId == coach.id }.count }

    /// In Chinese the Chinese name leads (as for athletes); else the name.
    private var names: (primary: String, secondary: String?) {
        let zh = coach.chineseName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !zh.isEmpty, zh != coach.name else { return (coach.name, nil) }
        return isChinese ? (zh, coach.name) : (coach.name, zh)
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(names.primary)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let secondary = names.secondary {
                        Text(secondary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if isYou {
                        Text(isChinese ? "我" : "You")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: .capsule)
                    }
                    if !coach.isActive { OrgInactiveTag() }
                }
                HStack(spacing: 4) {
                    Image(systemName: coach.role.icon)
                        .font(.caption2)
                        .foregroundStyle(coach.role.color)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            OrgChevron()
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        let programs = isChinese ? "\(programCount) 个项目"
            : (programCount == 1 ? "1 program" : "\(programCount) programs")
        return "\(coach.role.localizedName) · \(programs)"
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = Self.photo(of: coach, dataManager: dataManager) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            PanelAvatar(initials: coach.initials, color: Color.avatarColor(coach.avatarColor), size: 40)
        }
    }

    /// The coach's own photo; for you, the profile photo as a fallback.
    static func photo(of coach: StaffCoach, dataManager: DataManager) -> UIImage? {
        if let data = coach.profileImageData, let image = UIImage(data: data) { return image }
        guard coach.id == dataManager.loggedInCoachId else { return nil }
        if let data = dataManager.coach.profileImageData, let image = UIImage(data: data) { return image }
        guard let path = dataManager.coach.profileImageUrl, !path.isEmpty, !path.hasPrefix("http") else { return nil }
        let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Venue

struct OrgVenueRow: View {
    let location: Location
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        HStack(spacing: 12) {
            OrgIconTile(icon: location.courtType.icon, tint: location.courtType.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(location.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !location.isActive { OrgInactiveTag() }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            OrgChevron()
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        let courts = isChinese ? "\(location.courtCount) 块场地"
            : (location.courtCount == 1 ? "1 court" : "\(location.courtCount) courts")
        return [courts, location.fullAddress].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - School

struct OrgSchoolRow: View {
    let school: School
    @EnvironmentObject var dataManager: DataManager
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let programs = dataManager.programs.filter { $0.schoolId == school.id }
        let students = Set(programs.flatMap(\.enrolledStudentIds)).count
        HStack(spacing: 12) {
            OrgIconTile(icon: "building.columns.fill", tint: SessionFormat.school.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(school.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !school.isActive { OrgInactiveTag() }
                }
                Text(isChinese ? "\(programs.count) 个项目 · \(students) 名学员"
                     : "\(programs.count) \(programs.count == 1 ? "program" : "programs") · \(students) \(students == 1 ? "athlete" : "athletes")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            OrgChevron()
        }
        .contentShape(.rect)
    }
}

// MARK: - Age category

struct OrgCategoryRow: View {
    let category: CustomAgeCategory
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        HStack(spacing: 12) {
            AgeBadge(shortName: category.shortName, tint: category.color, size: .medium, filled: true)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !category.isActive { OrgInactiveTag() }
                }
                Text(isChinese ? "\(category.minAge)–\(category.maxAge) 岁 · \(category.ballSize.displayName) · \(category.rimHeight.displayName)"
                     : "Ages \(category.minAge)–\(category.maxAge) · \(category.ballSize.displayName) · \(category.rimHeight.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            OrgChevron()
        }
        .contentShape(.rect)
    }
}
