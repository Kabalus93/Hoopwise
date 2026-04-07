import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Attendance Reminder Sheet
/// Shows after session completion to remind coach to take attendance and photo
struct AttendanceReminderSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State var session: SessionEvent
    @State private var showAttendanceImagePicker = false
    @State private var capturedImage: PlatformImage?
    @State private var isSaving = false
    @State private var isEditingAttendance = true  // Keep list open until explicitly done
    @State private var uploadError: String?
    
    private var enrolledStudents: [Student] {
        guard let programId = session.programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
            return dataManager.students.filter { session.attendeeIds.contains($0.id) }
        }
        return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    private var attendanceComplete: Bool {
        !session.actualAttendeeIds.isEmpty && !isEditingAttendance
    }
    
    private var photoTaken: Bool {
        capturedImage != nil || session.attendancePhotoPath != nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Attendance Section
                    attendanceSection
                    
                    // Photo Section
                    photoSection
                    
                    // Action Buttons
                    actionButtons
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showAttendanceImagePicker) {
                AttendanceImagePicker(image: $capturedImage)
                    .ignoresSafeArea()
            }
            #endif
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text(session.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            Text("Session completed successfully!")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Attendance Section
    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(attendanceComplete ? .green : .orange)
                
                Text("ATTENDANCE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                if attendanceComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
            }
            
            if attendanceComplete {
                HStack {
                    Text("\(session.actualAttendeeIds.count) of \(enrolledStudents.count) students attended")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Spacer()
                    
                    Button(action: { isEditingAttendance = true }) {
                        Text("Edit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.accentColor)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Text("Mark who attended today's session")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Spacer()
                        
                        if !session.actualAttendeeIds.isEmpty {
                            Button(action: { 
                                isEditingAttendance = false
                                HapticFeedback.impact(.medium)
                            }) {
                                Text("Done")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Quick action buttons
                    HStack(spacing: 12) {
                        Button(action: { 
                            session.actualAttendeeIds = enrolledStudents.map { $0.id }
                            HapticFeedback.impact(.medium)
                        }) {
                            Text("All Present")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                        
                        Button(action: { 
                            session.actualAttendeeIds = []
                            HapticFeedback.impact(.light)
                        }) {
                            Text("Clear All")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppTheme.surfaceColor)
                                .cornerRadius(8)
                        }
                    }
                    
                    quickAttendanceList
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private var quickAttendanceList: some View {
        VStack(spacing: 8) {
            ForEach(enrolledStudents) { student in
                Button(action: {
                    toggleAttendance(for: student)
                }) {
                    HStack {
                        StudentAvatarView(student: student, size: 36)
                        
                        Text(student.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: session.actualAttendeeIds.contains(student.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(session.actualAttendeeIds.contains(student.id) ? .green : AppTheme.textTertiary)
                    }
                    .padding(10)
                    .background(session.actualAttendeeIds.contains(student.id) ? Color.green.opacity(0.1) : AppTheme.surfaceColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Photo Section
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16))
                    .foregroundColor(photoTaken ? .green : .blue)
                
                Text("ATTENDANCE PHOTO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                if photoTaken {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
            }
            
            if let image = capturedImage {
                photoPreview(image: image)
            } else if let photoPath = session.attendancePhotoPath {
                // Check if it's a URL or local path
                if photoPath.hasPrefix("http") {
                    urlPhotoPreview(url: photoPath)
                } else if let loadedImage = PhotoCaptureManager.shared.loadAttendancePhoto(from: photoPath) {
                    photoPreview(image: loadedImage)
                } else {
                    photoPlaceholder
                }
            } else {
                photoPlaceholder
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
    
    private func photoPreview(image: PlatformImage) -> some View {
        VStack(spacing: 12) {
            #if os(iOS)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            #elseif os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            #endif
            
            photoActionButtons
        }
    }
    
    private func urlPhotoPreview(url: String) -> some View {
        VStack(spacing: 12) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(height: 200)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                            .foregroundColor(.orange)
                        Text("Failed to load image")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(12)
                @unknown default:
                    EmptyView()
                }
            }
            
            photoActionButtons
        }
    }
    
    private var photoActionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { showAttendanceImagePicker = true }) {
                Label("Retake", systemImage: "camera.rotate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
            }
            
            Button(action: { 
                capturedImage = nil
                session.attendancePhotoPath = nil
            }) {
                Label("Remove", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(8)
            }
        }
    }
    
    private var photoPlaceholder: some View {
        Button(action: { showAttendanceImagePicker = true }) {
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.textTertiary)
                
                Text("Take Group Photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Capture a photo of all students as proof of attendance")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(AppTheme.surfaceColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: saveAndDismiss) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Save & Complete")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(isSaving)
            
            Text("Photo will be compressed to ~200KB to save storage")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
    
    // MARK: - Actions
    private func toggleAttendance(for student: Student) {
        if session.actualAttendeeIds.contains(student.id) {
            session.actualAttendeeIds.removeAll { $0 == student.id }
        } else {
            session.actualAttendeeIds.append(student.id)
        }
        HapticFeedback.impact(.light)
    }
    
    private func saveAndDismiss() {
        isSaving = true
        
        Task {
            // Save and upload photo if captured
            #if os(iOS)
            if let image = capturedImage {
                await uploadAttendancePhoto(image)
            }
            #endif
            
            // Update session
            await MainActor.run {
                dataManager.updateSessionEvent(session)
                HapticFeedback.notification(.success)
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    #if os(iOS)
    private func uploadAttendancePhoto(_ image: UIImage) async {
        // Resize image for memory efficiency (max 800px width for attendance photos)
        let resizedImage = resizeImage(image, maxWidth: 800)
        
        // Compress to JPEG - start with 0.6 quality, reduce if needed
        guard var imageData = resizedImage.jpegData(compressionQuality: 0.6) else {
            debugLog("❌ Failed to compress attendance photo")
            return
        }
        
        // Further compress if over 200KB target
        var quality: CGFloat = 0.6
        while imageData.count > 200 * 1024 && quality > 0.2 {
            quality -= 0.1
            if let compressed = resizedImage.jpegData(compressionQuality: quality) {
                imageData = compressed
            }
        }
        
        let sizeKB = Double(imageData.count) / 1024.0
        debugLog("📸 Attendance photo compressed to \(String(format: "%.1f", sizeKB))KB")
        
        // Save locally first as backup
        let localPath = PhotoCaptureManager.shared.saveAttendancePhoto(image, for: session.id)
        
        // Upload to Supabase
        if SupabaseManager.shared.isConnected {
            let path = "attendance/\(session.id.uuidString).jpg"
            
            do {
                let url = try await SupabaseManager.shared.uploadImage(
                    imageData: imageData,
                    bucket: "attendance-photos",
                    path: path
                )
                
                await MainActor.run {
                    session.attendancePhotoPath = url  // Store cloud URL
                }
                debugLog("✅ Attendance photo uploaded to Supabase: \(url)")
            } catch {
                debugLog("⚠️ Failed to upload to Supabase, using local path: \(error.localizedDescription)")
                await MainActor.run {
                    session.attendancePhotoPath = localPath
                    uploadError = error.localizedDescription
                }
            }
        } else {
            await MainActor.run {
                session.attendancePhotoPath = localPath
            }
            debugLog("📱 Offline - saved attendance photo locally")
        }
    }
    
    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        if size.width <= maxWidth { return image }
        
        let ratio = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
    #endif
}

// MARK: - Image Picker
#if os(iOS)
struct AttendanceImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        
        // Check camera availability
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        } else {
            // Fallback to photo library if camera unavailable
            picker.sourceType = .photoLibrary
        }
        
        // Ensure full screen presentation
        picker.modalPresentationStyle = .fullScreen
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: AttendanceImagePicker
        
        init(_ parent: AttendanceImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#elseif os(macOS)
struct AttendanceImagePicker: View {
    @Binding var image: NSImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Camera not available on macOS")
                .foregroundColor(AppTheme.textSecondary)
            
            Button("Choose from Files") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                
                if panel.runModal() == .OK, let url = panel.url {
                    image = NSImage(contentsOf: url)
                }
                dismiss()
            }
        }
        .padding()
    }
}
#endif
