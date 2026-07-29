import SwiftUI

// MARK: - Hoopwise Logo View
/// The official Hoopwise app logo - uses the actual logo image asset
/// Falls back to programmatic rendering if image is not available
struct HoopwiseLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true
    var animated: Bool = false
    
    @State private var animationProgress: CGFloat = 0
    
    var body: some View {
        Group {
            // Use the actual logo image from assets
            Image("HoopwiseLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        }
        .frame(width: size, height: size)
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    animationProgress = 1
                }
            }
        }
    }
    
    // MARK: - Fallback Programmatic Logo (kept for reference)
    @ViewBuilder
    private var fallbackLogo: some View {
        ZStack {
            if showBackground {
                logoBackground
            }
            logoContent
                .frame(width: size * 0.7, height: size * 0.7)
        }
    }
    
    // MARK: - Background
    private var logoBackground: some View {
        ZStack {
            // Gradient background
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.45, blue: 0.25), // Hoopwise Orange
                            Color(red: 0.85, green: 0.35, blue: 0.20)  // Darker orange
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle texture overlay
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
            
            // Inner shadow effect
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
    
    // MARK: - Logo Content
    private var logoContent: some View {
        let contentSize = size * 0.7
        let markerSize = contentSize * 0.18
        
        return ZStack {
            // Movement curve (the play line)
            MovementCurve(progress: animated ? animationProgress : 1)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: markerSize * 0.25,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: contentSize * 0.6, height: contentSize * 0.5)
                .offset(x: contentSize * 0.05, y: -contentSize * 0.05)
            
            // X marker (top right) - defender
            XMarker()
                .stroke(Color.white, style: StrokeStyle(lineWidth: markerSize * 0.2, lineCap: .round))
                .frame(width: markerSize, height: markerSize)
                .offset(x: contentSize * 0.2, y: -contentSize * 0.25)
            
            // Small x marker (bottom right)
            XMarker()
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: markerSize * 0.15, lineCap: .round))
                .frame(width: markerSize * 0.6, height: markerSize * 0.6)
                .offset(x: contentSize * 0.25, y: contentSize * 0.15)
            
            // O marker (bottom left) - ball handler
            Circle()
                .stroke(Color.white, lineWidth: markerSize * 0.2)
                .frame(width: markerSize, height: markerSize)
                .offset(x: -contentSize * 0.2, y: contentSize * 0.2)
            
            // Arrow head at end of curve
            ArrowHeadShape()
                .fill(Color.white)
                .frame(width: markerSize * 0.5, height: markerSize * 0.4)
                .rotationEffect(.degrees(-45))
                .offset(x: contentSize * 0.15, y: -contentSize * 0.3)
        }
    }
}

// MARK: - X Marker Shape
struct XMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.15
        
        // First diagonal
        path.move(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
        
        // Second diagonal
        path.move(to: CGPoint(x: rect.width - inset, y: inset))
        path.addLine(to: CGPoint(x: inset, y: rect.height - inset))
        
        return path
    }
}

// MARK: - Movement Curve Shape
struct MovementCurve: Shape {
    var progress: CGFloat = 1
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start from bottom left, curve up and to the right
        let startPoint = CGPoint(x: rect.width * 0.1, y: rect.height * 0.9)
        let endPoint = CGPoint(x: rect.width * 0.85, y: rect.height * 0.15)
        let controlPoint1 = CGPoint(x: rect.width * 0.1, y: rect.height * 0.3)
        let controlPoint2 = CGPoint(x: rect.width * 0.5, y: rect.height * 0.1)
        
        path.move(to: startPoint)
        path.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
        
        return path.trimmedPath(from: 0, to: progress)
    }
}

// MARK: - Arrow Head Shape
struct ArrowHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Compact Logo (for small spaces)
struct HoopwiseLogoCompact: View {
    var size: CGFloat = 32
    var color: Color = .orange
    
    var body: some View {
        ZStack {
            // Simple O
            Circle()
                .stroke(color, lineWidth: size * 0.08)
                .frame(width: size * 0.35, height: size * 0.35)
                .offset(x: -size * 0.15, y: size * 0.1)
            
            // Simple X
            XMarker()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: size * 0.12, y: -size * 0.08)
            
            // Curve
            MovementCurve()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .frame(width: size * 0.5, height: size * 0.4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Logo with Text
struct HoopwiseLogoWithText: View {
    var logoSize: CGFloat = 60
    var showTagline: Bool = true
    
    var body: some View {
        VStack(spacing: logoSize * 0.15) {
            HoopwiseLogoView(size: logoSize)
            
            VStack(spacing: 2) {
                Text("Hoopwise")
                    .font(.system(size: logoSize * 0.35, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .tracking(logoSize * 0.05)
                
                if showTagline {
                    Text("Basketball Training Manager")
                        .font(.system(size: logoSize * 0.12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Logo Sizes") {
    VStack(spacing: 30) {
        HStack(spacing: 20) {
            HoopwiseLogoView(size: 128)
            HoopwiseLogoView(size: 64)
            HoopwiseLogoView(size: 32)
        }
        
        HoopwiseLogoWithText(logoSize: 80)
        
        HStack(spacing: 20) {
            HoopwiseLogoCompact(size: 40, color: .orange)
            HoopwiseLogoCompact(size: 32, color: .blue)
            HoopwiseLogoCompact(size: 24, color: .gray)
        }
        
        HoopwiseLogoView(size: 100, animated: true)
    }
    .padding()
}
