import SwiftUI

/// Small profile sheet shown when tapping an @coach mention chip in notes
struct CoachMentionProfileSheet: View {
    let coach: StaffCoach
    @Environment(\.dismiss) private var dismiss

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Avatar
            ZStack {
                Circle()
                    .fill(Color(coach.avatarColor.color).opacity(0.2))
                    .frame(width: 80, height: 80)
                Text(coach.name.components(separatedBy: " ").compactMap { $0.first }.prefix(2).map(String.init).joined())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(coach.avatarColor.color))
            }
            .padding(.bottom, 12)

            // Name + role
            Text(coach.name)
                .font(.system(size: 20, weight: .bold))
            Text(coach.role.rawValue)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.top, 2)

            if let email = coach.email, !email.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .font(.system(size: 12))
                    Text(email)
                        .font(.system(size: 13))
                }
                .foregroundColor(.gray)
                .padding(.top, 6)
            }

            if let phone = coach.phone, !phone.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "phone")
                        .font(.system(size: 12))
                    Text(phone)
                        .font(.system(size: 13))
                }
                .foregroundColor(.gray)
                .padding(.top, 4)
            }

            // Specializations
            if !coach.specializations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(coach.specializations, id: \.self) { spec in
                            Text(spec)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(coach.avatarColor.color))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color(coach.avatarColor.color).opacity(0.12)))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 14)
            }

            // Access level badge
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 11))
                Text(coach.accessLevel.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(coach.avatarColor.color)))
            .padding(.top, 16)

            Spacer()

            Button(isChinese ? "关闭" : "Close") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 1.0, opacity: 1.0))
    }
}
