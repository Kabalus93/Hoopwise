import SwiftUI

struct PasswordResetView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var currentStep: ResetStep = .requestCode
    @State private var generatedCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    enum ResetStep {
        case requestCode
        case enterCode
        case newPassword
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Reset Password")
                            .font(.title.bold())
                        
                        Text(stepDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Content based on step
                    switch currentStep {
                    case .requestCode:
                        requestCodeView
                    case .enterCode:
                        enterCodeView
                    case .newPassword:
                        newPasswordView
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeadingCompat) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Password Reset Successful", isPresented: $showSuccess) {
                Button("Sign In") {
                    dismiss()
                }
            } message: {
                Text("Your password has been reset. You can now sign in with your new password.")
            }
        }
    }
    
    private var stepDescription: String {
        switch currentStep {
        case .requestCode:
            return "Enter your email address to receive a reset code"
        case .enterCode:
            return "Enter the 6-digit code sent to your email"
        case .newPassword:
            return "Create a new password for your account"
        }
    }
    
    // MARK: - Request Code View
    private var requestCodeView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                TextField("your@email.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalizationCompat(.never)
                    .keyboardTypeCompat(.emailAddress)
            }
            
            Button(action: requestCode) {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Request Reset Code")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(email.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(email.isEmpty || authManager.isLoading)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Enter Code View
    private var enterCodeView: some View {
        VStack(spacing: 20) {
            #if DEBUG
            if !generatedCode.isEmpty {
                VStack(spacing: 12) {
                    Text("Debug Reset Code:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(generatedCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.vertical)
            }
            #endif
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter Reset Code")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                TextField("000000", text: $resetCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardTypeCompat(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
            }
            
            Button(action: verifyCode) {
                Text("Verify Code")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(resetCode.count == 6 ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(resetCode.count != 6)
            
            Button("Request New Code") {
                currentStep = .requestCode
                resetCode = ""
                generatedCode = ""
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - New Password View
    private var newPasswordView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Password")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                SecureField("Enter new password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                SecureField("Confirm new password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }
            
            if !newPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: newPassword.count >= 6 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(newPassword.count >= 6 ? .green : .red)
                    Text("At least 6 characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !confirmPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: newPassword == confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(newPassword == confirmPassword ? .green : .red)
                    Text("Passwords match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button(action: resetPassword) {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Reset Password")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canResetPassword ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(!canResetPassword || authManager.isLoading)
        }
        .padding(.top, 20)
    }
    
    private var canResetPassword: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }
    
    // MARK: - Actions
    private func requestCode() {
        Task {
            do {
                generatedCode = try await authManager.requestPasswordReset(email: email)
                currentStep = .enterCode
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func verifyCode() {
        if resetCode.count == 6 {
            currentStep = .newPassword
        } else {
            errorMessage = "Invalid reset code. Please try again."
            showError = true
        }
    }
    
    private func resetPassword() {
        Task {
            do {
                try await authManager.resetPassword(email: email, resetCode: resetCode, newPassword: newPassword)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    PasswordResetView()
        .environmentObject(AuthManager.shared)
}
