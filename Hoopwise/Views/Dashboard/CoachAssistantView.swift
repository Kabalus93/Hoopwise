import SwiftUI

struct CoachAssistantView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var messages: [AssistantMessage] = []
    @State private var isProcessing = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    emptyStateView
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                inputBar
            }
            .background(Color(hex: "#f5f5f7").ignoresSafeArea())
            .navigationTitle(isChinese ? "教练助手" : "Coach Assistant")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeadingCompat) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailingCompat) {
                        Button(action: clearChat) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .onAppear {
                if messages.isEmpty {
                    addWelcomeMessage()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text(isChinese ? "你好！我是你的教练助手" : "Hi! I'm your Coach Assistant")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                
                Text(isChinese ? "问我关于学员、统计数据、课程或项目的任何问题" : "Ask me anything about students, stats, sessions, or programs")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                suggestionButton(
                    icon: "person.2.fill",
                    text: isChinese ? "哪些学员需要关注？" : "Which students need attention?",
                    action: { sendMessage(isChinese ? "哪些学员需要关注？" : "Which students need attention?") }
                )
                
                suggestionButton(
                    icon: "chart.bar.fill",
                    text: isChinese ? "显示本周的统计数据" : "Show me this week's stats",
                    action: { sendMessage(isChinese ? "显示本周的统计数据" : "Show me this week's stats") }
                )
                
                suggestionButton(
                    icon: "calendar.badge.clock",
                    text: isChinese ? "今天有哪些课程？" : "What sessions do I have today?",
                    action: { sendMessage(isChinese ? "今天有哪些课程？" : "What sessions do I have today?") }
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func suggestionButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
                    .frame(width: 24)
                
                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(.black)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
    }
    
    private var inputBar: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return HStack(spacing: 12) {
            TextField(isChinese ? "输入消息..." : "Type a message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white)
                .cornerRadius(20)
                .lineLimit(1...5)
                .focused($isInputFocused)
            
            Button(action: {
                sendMessage(messageText)
                messageText = ""
            }) {
                ZStack {
                    Circle()
                        .fill(messageText.isEmpty ? Color.gray.opacity(0.3) : Color.purple)
                        .frame(width: 40, height: 40)
                    
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(messageText.isEmpty || isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#f5f5f7"))
    }
    
    private func addWelcomeMessage() {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let welcomeText = isChinese ? 
            "你好！我是你的教练助手。我可以帮助你查找学员信息、分析统计数据、管理课程和项目。有什么我可以帮助你的吗？" :
            "Hello! I'm your Coach Assistant. I can help you find student information, analyze stats, manage sessions and programs. What can I help you with?"
        
        messages.append(AssistantMessage(text: welcomeText, isUser: false))
    }
    
    private func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = AssistantMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let response = processQuery(text)
            messages.append(AssistantMessage(text: response, isUser: false))
            isProcessing = false
            HapticFeedback.notification(.success)
        }
    }
    
    private func processQuery(_ query: String) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let lowercased = query.lowercased()
        
        // Students needing attention
        if lowercased.contains("attention") || lowercased.contains("关注") || lowercased.contains("需要") {
            // Find students with poor attendance as a proxy for needing attention
            let needsAttention = dataManager.students.filter { student in
                student.attendanceStatus == .absent || student.attendanceStatus == .late
            }
            
            if needsAttention.isEmpty {
                return isChinese ? "太好了！目前没有学员需要特别关注。" : "Great! No students currently need special attention."
            }
            
            let studentList = needsAttention.prefix(5).map { "• \($0.name)" }.joined(separator: "\n")
            return isChinese ? 
                "以下学员需要关注：\n\n\(studentList)\n\n建议尽快联系这些学员的家长。" :
                "These students need attention:\n\n\(studentList)\n\nI recommend contacting their parents soon."
        }
        
        // Today's sessions
        if lowercased.contains("today") || lowercased.contains("今天") || lowercased.contains("session") || lowercased.contains("课程") {
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            
            let todaySessions = dataManager.sessionEvents.filter { session in
                session.date >= today && session.date < tomorrow
            }
            
            if todaySessions.isEmpty {
                return isChinese ? "今天没有安排课程。" : "No sessions scheduled for today."
            }
            
            let sessionList = todaySessions.map { session in
                let time = session.date.formatted(date: .omitted, time: .shortened)
                return "• \(session.title) - \(time)"
            }.joined(separator: "\n")
            
            return isChinese ?
                "今天的课程：\n\n\(sessionList)" :
                "Today's sessions:\n\n\(sessionList)"
        }
        
        // Stats
        if lowercased.contains("stats") || lowercased.contains("统计") || lowercased.contains("数据") {
            let totalStudents = dataManager.students.count
            let activeContracts = dataManager.students.filter { student in
                guard let contract = dataManager.currentContract(for: student.id) else { return false }
                return contract.status == .active
            }.count
            let totalSessions = dataManager.sessionEvents.count
            
            return isChinese ?
                "📊 统计概览：\n\n• 学员总数：\(totalStudents)\n• 有效合同：\(activeContracts)\n• 课程总数：\(totalSessions)" :
                "📊 Stats Overview:\n\n• Total Students: \(totalStudents)\n• Active Contracts: \(activeContracts)\n• Total Sessions: \(totalSessions)"
        }
        
        // Find student
        if lowercased.contains("find") || lowercased.contains("查找") || lowercased.contains("search") || lowercased.contains("搜索") {
            return isChinese ?
                "我可以帮你查找学员。请告诉我学员的名字或其他信息。" :
                "I can help you find a student. Please tell me the student's name or other details."
        }
        
        // Default response
        return isChinese ?
            "我理解你的问题。目前我可以帮助你：\n\n• 查找需要关注的学员\n• 查看今天的课程安排\n• 显示统计数据\n• 查找特定学员\n\n请告诉我你想了解什么？" :
            "I understand your question. Currently I can help you:\n\n• Find students needing attention\n• View today's schedule\n• Show statistics\n• Find specific students\n\nWhat would you like to know?"
    }
    
    private func clearChat() {
        messages.removeAll()
        addWelcomeMessage()
        HapticFeedback.notification(.success)
    }
}

struct AssistantMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

struct MessageBubble: View {
    let message: AssistantMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(message.isUser ? .white : .black)
                    .padding(12)
                    .background(
                        message.isUser ?
                            AnyView(LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )) :
                            AnyView(Color.white)
                    )
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}
