import SwiftUI
import Speech
import AVFoundation
import Combine

// MARK: - Enhanced Notes Section with Speech-to-Text
struct EnhancedNotesSection: View {
    let title: String
    let icon: String
    @Binding var text: String
    let placeholder: String
    let canEdit: Bool
    let onSave: () -> Void
    
    @State private var isRecording = false
    @State private var showingSpeechError = false
    @State private var speechErrorMessage = ""
    @State private var isExpanded = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and action buttons
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if canEdit {
                    // Expand/collapse button
                    Button(action: { 
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    
                    // Speech-to-text button
                    Button(action: toggleRecording) {
                        HStack(spacing: 4) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(isRecording ? .red : .blue)
                            if isRecording {
                                Text(isChinese ? "录音中..." : "Recording...")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if canEdit {
                // Editable text area
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: isExpanded ? 250 : 120, maxHeight: isExpanded ? 400 : 200)
                    .padding(14)
                    #if canImport(UIKit)
                    .background(Color(UIColor.systemBackground))
                    #else
                    .background(Color(NSColor.windowBackgroundColor))
                    #endif
                    .cornerRadius(12)
                    .overlay(
                        Group {
                            if text.isEmpty {
                                Text(placeholder)
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(18)
                            }
                        },
                        alignment: .topLeading
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isRecording ? Color.red.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    .onChange(of: text) { _, _ in
                        onSave()
                    }
                
                // Character count and formatting hints
                HStack {
                    Text("\(text.count) " + (isChinese ? "字符" : "characters"))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    if isRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .opacity(pulsingAnimation ? 1 : 0.3)
                            Text(isChinese ? "正在聆听..." : "Listening...")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                }
            } else {
                // Read-only view
                Text(text.isEmpty ? (isChinese ? "暂无笔记" : "No notes") : text)
                    .font(.system(size: 15))
                    .foregroundColor(text.isEmpty ? .gray : .primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if canImport(UIKit)
                    .background(Color(UIColor.systemBackground))
                    #else
                    .background(Color(NSColor.windowBackgroundColor))
                    #endif
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            }
        }
        .alert(isChinese ? "语音识别错误" : "Speech Recognition Error", isPresented: $showingSpeechError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(speechErrorMessage)
        }
        .onReceive(speechRecognizer.$transcript) { newTranscript in
            if isRecording && !newTranscript.isEmpty {
                // Append transcribed text
                if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n") {
                    text += " "
                }
                text += newTranscript
            }
        }
    }
    
    @State private var pulsingAnimation = false
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    // iOS 17+ uses AVAudioApplication instead of AVAudioSession for permission
                    Task {
                        do {
                            let granted = await AVAudioApplication.requestRecordPermission()
                            await MainActor.run {
                                if granted {
                                    do {
                                        // Determine language based on app setting
                                        let locale = isChinese ? Locale(identifier: "zh-CN") : Locale(identifier: "en-US")
                                        try speechRecognizer.startRecording(locale: locale)
                                        isRecording = true
                                        HapticFeedback.impact(.medium)
                                        
                                        // Start pulsing animation
                                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                            pulsingAnimation = true
                                        }
                                    } catch {
                                        speechErrorMessage = error.localizedDescription
                                        showingSpeechError = true
                                    }
                                } else {
                                    speechErrorMessage = isChinese ? "需要麦克风权限才能使用语音输入" : "Microphone permission is required for voice input"
                                    showingSpeechError = true
                                }
                            }
                        }
                    }
                case .denied, .restricted:
                    speechErrorMessage = isChinese ? "语音识别权限被拒绝。请在设置中启用。" : "Speech recognition permission denied. Please enable in Settings."
                    showingSpeechError = true
                case .notDetermined:
                    speechErrorMessage = isChinese ? "语音识别权限未确定" : "Speech recognition permission not determined"
                    showingSpeechError = true
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func stopRecording() {
        speechRecognizer.stopRecording()
        isRecording = false
        pulsingAnimation = false
        HapticFeedback.impact(.light)
        onSave()
    }
}

// MARK: - Speech Recognizer
class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    
    func startRecording(locale: Locale) throws {
        // Reset
        transcript = ""
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        
        // Initialize recognizer with specified locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available for this language"])
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw NSError(domain: "SpeechRecognizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create audio engine"])
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    // Only update with final results to avoid duplicates
                    if result.isFinal {
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine?.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Reset audio session
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }
}

// MARK: - Previous Session Notes Summary View
struct PreviousSessionNotesSummary: View {
    let previousNotes: String?
    let previousCoachNotes: String?
    let previousSessionDate: Date?
    @Binding var isExpanded: Bool
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    private var hasNotes: Bool {
        (previousNotes != nil && !previousNotes!.isEmpty) ||
        (previousCoachNotes != nil && !previousCoachNotes!.isEmpty)
    }
    
    var body: some View {
        if hasNotes {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text(isChinese ? "上次课程笔记" : "PREVIOUS SESSION NOTES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        
                        if let date = previousSessionDate {
                            Text("• \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        // Session notes
                        if let notes = previousNotes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isChinese ? "课程笔记" : "Session Notes")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.gray)
                                Text(notes)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineLimit(5)
                            }
                        }
                        
                        // Coach reflections
                        if let coachNotes = previousCoachNotes, !coachNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isChinese ? "教练反思" : "Coach Reflections")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.gray)
                                Text(coachNotes)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineLimit(5)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(10)
                }
            }
            .padding(14)
            #if canImport(UIKit)
            .background(Color(UIColor.systemBackground))
            #else
            .background(Color(NSColor.windowBackgroundColor))
            #endif
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}
