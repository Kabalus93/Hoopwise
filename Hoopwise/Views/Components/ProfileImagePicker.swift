import SwiftUI
import PhotosUI

#if os(iOS)
struct ProfileImagePicker: View {
    @Binding var imageData: Data?
    var size: CGFloat = 100
    var placeholderIcon: String = "person.circle.fill"
    var placeholderColor: Color = .gray
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingOptions = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: placeholderIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundColor(placeholderColor.opacity(0.5))
                }
                
                // Camera overlay button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.15))
                            .foregroundColor(.white)
                            .padding(size * 0.06)
                            .background(Circle().fill(Color.blue))
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
                .frame(width: size, height: size)
            }
            .onTapGesture {
                showingOptions = true
            }
        }
        .confirmationDialog("Profile Photo", isPresented: $showingOptions) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Choose from Library")
            }
            if imageData != nil {
                Button("Remove Photo", role: .destructive) {
                    withAnimation {
                        imageData = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    // Compress image to reasonable size
                    if let uiImage = UIImage(data: data) {
                        let compressed = uiImage.jpegData(compressionQuality: 0.5)
                        await MainActor.run {
                            withAnimation {
                                imageData = compressed
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ProfileImageView: View {
    let imageData: Data?
    var size: CGFloat = 40
    var placeholderIcon: String = "person.circle.fill"
    var placeholderColor: Color = .gray
    
    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: placeholderIcon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundColor(placeholderColor.opacity(0.5))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfileImagePicker(imageData: .constant(nil))
        ProfileImageView(imageData: nil, size: 60)
    }
    .padding()
}
#endif
