import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Onboarding (single-coach local-only)
/// First-launch flow: ask for the coach's name and (optional) photo, then drop them on the dashboard.
/// The device owner is always the coach in the local-only build.
struct OnboardingView: View {
    @EnvironmentObject var dataManager: DataManager
    var onComplete: () -> Void

    @State private var name: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @FocusState private var nameFocused: Bool

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text(isChinese ? "欢迎来到 Hoopwise" : "Welcome to Hoopwise")
                    .font(.system(size: 28, weight: .bold))
                Text(isChinese ? "请输入您的姓名" : "Tell us your name to get started")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            // Photo picker
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 120, height: 120)

                    if let imageData,
                       let img = platformImage(from: imageData) {
                        platformImageView(img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 116, height: 116)
                            .clipShape(Circle())
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentColor)
                            Text(isChinese ? "添加照片" : "Add Photo")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 32)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { imageData = data }
                    }
                }
            }

            // Name field
            TextField(isChinese ? "您的姓名" : "Your name", text: $name)
                .textContentType(.name)
                .focused($nameFocused)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 24)

            Spacer()

            // Continue
            Button(isChinese ? "继续" : "Continue", action: complete)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
                .frame(maxWidth: .infinity)
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear { nameFocused = true }
    }

    private func complete() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var coach = dataManager.coach
        coach.name = trimmed
        if let imageData { coach.profileImageData = imageData }
        coach.updatedAt = Date()
        dataManager.updateCoach(coach)

        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        onComplete()
    }

    #if os(iOS)
    private func platformImage(from data: Data) -> UIImage? { UIImage(data: data) }
    private func platformImageView(_ image: UIImage) -> Image { Image(uiImage: image) }
    #else
    private func platformImage(from data: Data) -> NSImage? { NSImage(data: data) }
    private func platformImageView(_ image: NSImage) -> Image { Image(nsImage: image) }
    #endif
}
