import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit
#endif

// MARK: - Roll Call Photo Sheet
struct RollCallPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let programColor: Color
    /// Why the sheet is up: the engine's reminder near the end of a running
    /// class, or the coach completing the session.
    var reason: Reason = .endingSoon
    let onCaptured: (PlatformImage) -> Void

    enum Reason { case endingSoon, completed, manual }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var message: String {
        switch reason {
        case .endingSoon:
            return isChinese
                ? "本节课还剩 5 分钟。拍一张合照记录到场学员，照片会保存到这节课。"
                : "5 minutes left in this session. Snap a quick group photo to record who was there — it'll be saved to this session."
        case .completed:
            return isChinese
                ? "课程已完成。拍一张合照记录到场学员，照片会保存到这节课。"
                : "Session complete. Snap a quick group photo to record who was there — it'll be saved to this session."
        case .manual:
            return isChinese
                ? "拍一张合照记录到场学员，照片会保存到这节课。"
                : "Snap a quick group photo to record who was there — it'll be saved to this session."
        }
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var loadedImage: PlatformImage?
    #if os(iOS)
    @State private var showingCamera = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                Text(isChinese ? "点名合照" : "Roll-call photo")
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let img = loadedImage {
                    #if os(iOS)
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    #else
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    #endif
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    #if os(iOS)
                    Button {
                        showingCamera = true
                    } label: {
                        Label(isChinese ? "拍照" : "Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    #endif

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(isChinese ? "从相册选择" : "Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if loadedImage != nil {
                        Button {
                            if let img = loadedImage { onCaptured(img); dismiss() }
                        } label: {
                            Label(isChinese ? "保存到本节课" : "Save to session", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle(isChinese ? "点名" : "Roll Call")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "跳过" : "Skip") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = PlatformImage(data: data) {
                        await MainActor.run { loadedImage = img }
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: Binding(
                    get: { loadedImage },
                    set: { loadedImage = $0 }
                ))
            }
            #endif
        }
    }
}
