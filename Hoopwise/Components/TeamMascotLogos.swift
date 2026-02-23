import SwiftUI

// MARK: - Team Mascot Type
enum TeamMascotType: String, CaseIterable, Codable {
    case tiger, snowLeopard, leopard, alligator, cobra
    case mastiff, yak, takin, horse, bear
    case monkey, eagle, squirrel, deer, falcon
    case panda, redPanda, pangolin, salamander, crane
    
    var displayName: String {
        switch self {
        case .tiger: return "Strikers"
        case .snowLeopard: return "Shadows"
        case .leopard: return "Claws"
        case .alligator: return "Jaws"
        case .cobra: return "Venom"
        case .mastiff: return "Guardians"
        case .yak: return "Stampede"
        case .takin: return "Torment"
        case .horse: return "Horsepower"
        case .bear: return "Rage"
        case .monkey: return "Mayhem"
        case .eagle: return "Talons"
        case .squirrel: return "Gliders"
        case .deer: return "Swift"
        case .falcon: return "Dive"
        case .panda: return "Fury"
        case .redPanda: return "Flames"
        case .pangolin: return "Armor"
        case .salamander: return "Salamander"
        case .crane: return "Flight"
        }
    }
    
    var fullName: String {
        switch self {
        case .tiger: return "Siberian Strikers"
        case .snowLeopard: return "Snow Leopard Shadows"
        case .leopard: return "Clouded Leopard Claws"
        case .alligator: return "Chinese Alligator Jaws"
        case .cobra: return "King Cobra Venom"
        case .mastiff: return "Tibetan Mastiff Guardians"
        case .yak: return "Wild Yak Stampede"
        case .takin: return "Takin Torment"
        case .horse: return "Przewalski Horsepower"
        case .bear: return "Moon Bear Rage"
        case .monkey: return "Golden Monkey Mayhem"
        case .eagle: return "Golden Eagle Talons"
        case .squirrel: return "Flying Squirrel Gliders"
        case .deer: return "Sika Deer Swift"
        case .falcon: return "Peregrine Falcon Dive"
        case .panda: return "Giant Panda Fury"
        case .redPanda: return "Red Panda Flames"
        case .pangolin: return "Pangolin Armor"
        case .salamander: return "Giant Salamander"
        case .crane: return "Red-Crowned Crane Flight"
        }
    }
    
    var shortName: String {
        switch self {
        case .tiger: return "STR"
        case .snowLeopard: return "SLS"
        case .leopard: return "CLC"
        case .alligator: return "JAW"
        case .cobra: return "VNM"
        case .mastiff: return "TMG"
        case .yak: return "YAK"
        case .takin: return "TAK"
        case .horse: return "PHP"
        case .bear: return "MBR"
        case .monkey: return "GMM"
        case .eagle: return "GET"
        case .squirrel: return "GLI"
        case .deer: return "SDS"
        case .falcon: return "PFD"
        case .panda: return "GPF"
        case .redPanda: return "RPF"
        case .pangolin: return "PAN"
        case .salamander: return "SAL"
        case .crane: return "RCF"
        }
    }
    
    /// Fallback SF Symbol for when custom mascot isn't available
    var fallbackIcon: String {
        switch self {
        case .tiger: return "cat.fill"
        case .snowLeopard: return "snowflake.circle.fill"
        case .leopard: return "pawprint.circle.fill"
        case .alligator: return "mouth.fill"
        case .cobra: return "bolt.circle.fill"
        case .mastiff: return "dog.circle.fill"
        case .yak: return "hurricane"
        case .takin: return "mountain.2.circle.fill"
        case .horse: return "hare.fill"
        case .bear: return "moon.circle.fill"
        case .monkey: return "figure.climbing"
        case .eagle: return "bird.circle.fill"
        case .squirrel: return "wind.circle.fill"
        case .deer: return "leaf.circle.fill"
        case .falcon: return "arrow.down.circle.fill"
        case .panda: return "circle.hexagongrid.circle.fill"
        case .redPanda: return "flame.circle.fill"
        case .pangolin: return "shield.checkered"
        case .salamander: return "drop.circle.fill"
        case .crane: return "bird.fill"
        }
    }
    
    var primaryColorHex: String {
        switch self {
        case .tiger: return "#F97316"
        case .snowLeopard: return "#94A3B8"
        case .leopard: return "#FBBF24"
        case .alligator: return "#22C55E"
        case .cobra: return "#10B981"
        case .mastiff: return "#B45309"
        case .yak: return "#78716C"
        case .takin: return "#EAB308"
        case .horse: return "#A16207"
        case .bear: return "#1F2937"
        case .monkey: return "#F59E0B"
        case .eagle: return "#CA8A04"
        case .squirrel: return "#6B7280"
        case .deer: return "#84CC16"
        case .falcon: return "#3B82F6"
        case .panda: return "#1F2937"
        case .redPanda: return "#DC2626"
        case .pangolin: return "#A8A29E"
        case .salamander: return "#854D0E"
        case .crane: return "#EF4444"
        }
    }
    
    var secondaryColorHex: String {
        switch self {
        case .tiger: return "#7C2D12"
        case .snowLeopard: return "#1E293B"
        case .leopard: return "#78350F"
        case .alligator: return "#14532D"
        case .cobra: return "#064E3B"
        case .mastiff: return "#451A03"
        case .yak: return "#292524"
        case .takin: return "#713F12"
        case .horse: return "#422006"
        case .bear: return "#EF4444"
        case .monkey: return "#166534"
        case .eagle: return "#1C1917"
        case .squirrel: return "#1F2937"
        case .deer: return "#365314"
        case .falcon: return "#1E3A8A"
        case .panda: return "#F9FAFB"
        case .redPanda: return "#F97316"
        case .pangolin: return "#44403C"
        case .salamander: return "#1C1917"
        case .crane: return "#F5F5F4"
        }
    }
    
    var accentColorHex: String {
        switch self {
        case .tiger: return "#FBBF24"
        case .snowLeopard: return "#E2E8F0"
        case .leopard: return "#FDE68A"
        case .alligator: return "#4ADE80"
        case .cobra: return "#6EE7B7"
        case .mastiff: return "#D97706"
        case .yak: return "#A8A29E"
        case .takin: return "#FDE047"
        case .horse: return "#CA8A04"
        case .bear: return "#374151"
        case .monkey: return "#FCD34D"
        case .eagle: return "#EAB308"
        case .squirrel: return "#9CA3AF"
        case .deer: return "#A3E635"
        case .falcon: return "#60A5FA"
        case .panda: return "#FFFFFF"
        case .redPanda: return "#FCA5A5"
        case .pangolin: return "#D6D3D1"
        case .salamander: return "#A16207"
        case .crane: return "#FCA5A5"
        }
    }
}

// MARK: - Enhanced Team Mascot Logo
struct TeamMascotLogo: View {
    let mascot: TeamMascotType
    var size: CGFloat = 60
    var showGlow: Bool = true
    
    private var primaryColor: Color { Color(hex: mascot.primaryColorHex) }
    private var secondaryColor: Color { Color(hex: mascot.secondaryColorHex) }
    private var accentColor: Color { Color(hex: mascot.accentColorHex) }
    
    var body: some View {
        ZStack {
            // Outer glow
            if showGlow {
                Circle()
                    .fill(RadialGradient(
                        colors: [accentColor.opacity(0.5), primaryColor.opacity(0.2), .clear],
                        center: .center, startRadius: size * 0.3, endRadius: size * 0.7
                    ))
                    .frame(width: size * 1.4, height: size * 1.4)
            }
            
            // Background shape
            backgroundView(gradient: LinearGradient(
                colors: [accentColor, primaryColor, secondaryColor],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            
            // Highlight overlay
            backgroundView(gradient: LinearGradient(
                colors: [.white.opacity(0.35), .clear, .black.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            
            // Mascot face
            mascotContent
                .frame(width: size * 0.7, height: size * 0.7)
        }
        .shadow(color: primaryColor.opacity(0.4), radius: size * 0.12, x: 0, y: size * 0.06)
    }
    
    private var backgroundStyle: BackgroundStyle {
        switch mascot {
        case .tiger, .leopard, .snowLeopard, .bear, .mastiff:
            return .shield
        case .eagle, .falcon, .crane:
            return .hexagon
        default:
            return .circle
        }
    }
    
    enum BackgroundStyle {
        case circle, shield, hexagon
    }
    
    @ViewBuilder
    private func backgroundView(gradient: LinearGradient) -> some View {
        switch backgroundStyle {
        case .circle:
            Circle().fill(gradient)
        case .shield:
            ShieldShape().fill(gradient)
        case .hexagon:
            HexagonShape().fill(gradient)
        }
    }
    
    @ViewBuilder
    private var mascotContent: some View {
        switch mascot {
        case .tiger: TigerFace()
        case .snowLeopard: CatFace(baseColor: Color(hex: "#CBD5E1"), spotColor: Color(hex: "#475569"), eyeColor: Color(hex: "#38BDF8"))
        case .leopard: CatFace(baseColor: Color(hex: "#FCD34D"), spotColor: Color(hex: "#92400E"), eyeColor: Color(hex: "#B45309"))
        case .alligator: AlligatorFace()
        case .cobra: CobraFace()
        case .mastiff: DogFace(baseColor: Color(hex: "#92400E"), muzzleColor: Color(hex: "#FED7AA"))
        case .yak: YakFace()
        case .takin: DogFace(baseColor: Color(hex: "#CA8A04"), muzzleColor: Color(hex: "#FEF3C7"))
        case .horse: HorseFace()
        case .bear: BearFace()
        case .monkey: MonkeyFace()
        case .eagle: EagleFace()
        case .squirrel: DogFace(baseColor: Color(hex: "#6B7280"), muzzleColor: Color(hex: "#E5E7EB"))
        case .deer: DeerFace()
        case .falcon: FalconFace()
        case .panda: PandaFace()
        case .redPanda: RedPandaFace()
        case .pangolin: PangolinFace()
        case .salamander: SalamanderFace()
        case .crane: CraneFace()
        }
    }
}

// MARK: - Background Shapes
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w * 0.85, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.55))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w, y: h * 0.85))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.55), control: CGPoint(x: 0, y: h * 0.85))
        path.addLine(to: CGPoint(x: 0, y: h * 0.2))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0), control: CGPoint(x: w * 0.15, y: 0))
        return path
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.93, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.93, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: w * 0.07, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.07, y: h * 0.25))
        path.closeSubpath()
        return path
    }
}

// MARK: - Mascot Faces
struct TigerFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color.orange).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Ellipse().fill(Color.white).frame(width: w * 0.5, height: h * 0.35).position(x: w/2, y: h * 0.65)
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color.black)
                        .frame(width: w * 0.06, height: h * 0.2)
                        .rotationEffect(.degrees(Double(i - 1) * 12))
                        .position(x: w * (0.35 + CGFloat(i) * 0.15), y: h * 0.28)
                }
                EyePair(w: w, h: h, eyeColor: .black)
                Ellipse().fill(Color.black).frame(width: w * 0.12, height: h * 0.08).position(x: w/2, y: h * 0.55)
            }
        }
    }
}

struct CatFace: View {
    let baseColor: Color
    let spotColor: Color
    let eyeColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(baseColor).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Ellipse().fill(Color.white).frame(width: w * 0.5, height: h * 0.35).position(x: w/2, y: h * 0.65)
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(spotColor).frame(width: w * 0.08)
                        .position(x: w * (0.25 + CGFloat(i % 2) * 0.5), y: h * (0.3 + CGFloat(i / 2) * 0.15))
                }
                EyePair(w: w, h: h, eyeColor: eyeColor)
                Ellipse().fill(Color.black).frame(width: w * 0.1, height: h * 0.07).position(x: w/2, y: h * 0.55)
            }
        }
    }
}

struct DogFace: View {
    let baseColor: Color
    let muzzleColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(baseColor).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Circle().fill(baseColor.opacity(0.8)).frame(width: w * 0.22).position(x: w * 0.2, y: h * 0.18)
                Circle().fill(baseColor.opacity(0.8)).frame(width: w * 0.22).position(x: w * 0.8, y: h * 0.18)
                Ellipse().fill(muzzleColor).frame(width: w * 0.5, height: h * 0.38).position(x: w/2, y: h * 0.62)
                EyePair(w: w, h: h, eyeColor: .black)
                Ellipse().fill(Color.black).frame(width: w * 0.12, height: h * 0.08).position(x: w/2, y: h * 0.55)
            }
        }
    }
}

struct AlligatorFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#166534"))
                    .frame(width: w * 0.95, height: h * 0.45).position(x: w/2, y: h * 0.68)
                Ellipse().fill(Color(hex: "#15803D")).frame(width: w * 0.7, height: h * 0.45).position(x: w/2, y: h * 0.35)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#FDE047"), yPos: 0.3, pupilColor: .black)
                ForEach(0..<4, id: \.self) { i in
                    Triangle().fill(Color.white).frame(width: w * 0.08, height: h * 0.1)
                        .position(x: w * (0.25 + CGFloat(i) * 0.18), y: h * 0.85)
                }
            }
        }
    }
}

struct CobraFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#059669")).frame(width: w * 0.95, height: h * 0.9).position(x: w/2, y: h/2)
                Ellipse().fill(Color(hex: "#FDE047")).frame(width: w * 0.25, height: h * 0.15).position(x: w/2, y: h * 0.35)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#FDE047"), yPos: 0.45, slitPupil: true)
                // Tongue
                Path { p in
                    p.move(to: CGPoint(x: w/2, y: h * 0.7))
                    p.addLine(to: CGPoint(x: w/2, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.95))
                    p.move(to: CGPoint(x: w/2, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.95))
                }.stroke(Color.red, lineWidth: 2)
            }
        }
    }
}

struct YakFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#44403C")).frame(width: w * 0.95, height: h * 0.85).position(x: w/2, y: h * 0.55)
                // Horns
                Path { p in
                    p.move(to: CGPoint(x: w * 0.2, y: h * 0.4))
                    p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.15), control: CGPoint(x: w * 0.05, y: h * 0.4))
                }.stroke(Color(hex: "#A8A29E"), lineWidth: 4)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.8, y: h * 0.4))
                    p.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.15), control: CGPoint(x: w * 0.95, y: h * 0.4))
                }.stroke(Color(hex: "#A8A29E"), lineWidth: 4)
                Ellipse().fill(Color(hex: "#57534E")).frame(width: w * 0.55, height: h * 0.45).position(x: w/2, y: h * 0.58)
                EyePair(w: w, h: h, eyeColor: .black, yPos: 0.48)
                Ellipse().fill(Color.black).frame(width: w * 0.12, height: h * 0.08).position(x: w/2, y: h * 0.68)
            }
        }
    }
}

struct HorseFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#A16207")).frame(width: w * 0.65, height: h * 0.95).position(x: w/2, y: h/2)
                ForEach(0..<4, id: \.self) { i in
                    Ellipse().fill(Color(hex: "#422006")).frame(width: w * 0.12, height: h * 0.18)
                        .position(x: w * 0.28, y: h * (0.2 + CGFloat(i) * 0.18))
                }
                EyePair(w: w, h: h, eyeColor: .black, yPos: 0.38, xSpread: 0.12)
                Ellipse().fill(Color.black).frame(width: w * 0.08, height: h * 0.05).position(x: w * 0.58, y: h * 0.75)
            }
        }
    }
}

struct BearFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#1F2937")).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Circle().fill(Color(hex: "#1F2937")).frame(width: w * 0.22).position(x: w * 0.2, y: h * 0.18)
                Circle().fill(Color(hex: "#1F2937")).frame(width: w * 0.22).position(x: w * 0.8, y: h * 0.18)
                Ellipse().fill(Color(hex: "#374151")).frame(width: w * 0.42, height: h * 0.32).position(x: w/2, y: h * 0.62)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#EF4444"), yPos: 0.42)
                Ellipse().fill(Color.black).frame(width: w * 0.12, height: h * 0.08).position(x: w/2, y: h * 0.55)
            }
        }
    }
}

struct MonkeyFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#F59E0B")).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Ellipse().fill(Color(hex: "#FEF3C7")).frame(width: w * 0.58, height: h * 0.52).position(x: w/2, y: h * 0.55)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#78350F"), yPos: 0.42)
                Ellipse().fill(Color(hex: "#92400E")).frame(width: w * 0.1, height: h * 0.06).position(x: w/2, y: h * 0.58)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.4, y: h * 0.68))
                    p.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.68), control: CGPoint(x: w/2, y: h * 0.78))
                }.stroke(Color(hex: "#92400E"), lineWidth: 2)
            }
        }
    }
}

struct EagleFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#CA8A04")).frame(width: w * 0.85, height: h * 0.65).position(x: w/2, y: h * 0.4)
                Ellipse().fill(Color.white).frame(width: w * 0.68, height: h * 0.5).position(x: w/2, y: h * 0.45)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#FDE047"), yPos: 0.4, pupilColor: .black)
                Triangle().fill(Color(hex: "#F59E0B")).frame(width: w * 0.25, height: h * 0.35).position(x: w/2, y: h * 0.72)
            }
        }
    }
}

struct DeerFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Antlers
                Path { p in
                    p.move(to: CGPoint(x: w * 0.28, y: h * 0.4))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.18))
                }.stroke(Color(hex: "#78350F"), lineWidth: 3)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.72, y: h * 0.4))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.18))
                }.stroke(Color(hex: "#78350F"), lineWidth: 3)
                Ellipse().fill(Color(hex: "#84CC16")).frame(width: w * 0.72, height: h * 0.6).position(x: w/2, y: h * 0.55)
                EyePair(w: w, h: h, eyeColor: .black, yPos: 0.48)
                Ellipse().fill(Color.black).frame(width: w * 0.1, height: h * 0.06).position(x: w/2, y: h * 0.65)
            }
        }
    }
}

struct FalconFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#3B82F6")).frame(width: w * 0.8, height: h * 0.68).position(x: w/2, y: h * 0.45)
                Path { p in p.move(to: CGPoint(x: w * 0.32, y: h * 0.35)); p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.68)) }.stroke(Color.black, lineWidth: 3)
                Path { p in p.move(to: CGPoint(x: w * 0.68, y: h * 0.35)); p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.68)) }.stroke(Color.black, lineWidth: 3)
                EyePair(w: w, h: h, eyeColor: Color(hex: "#FDE047"), yPos: 0.42, pupilColor: .black)
                Triangle().fill(Color(hex: "#1E3A8A")).frame(width: w * 0.2, height: h * 0.28).position(x: w/2, y: h * 0.7)
            }
        }
    }
}

struct PandaFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color.white).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Circle().fill(Color.black).frame(width: w * 0.22).position(x: w * 0.2, y: h * 0.18)
                Circle().fill(Color.black).frame(width: w * 0.22).position(x: w * 0.8, y: h * 0.18)
                Ellipse().fill(Color.black).frame(width: w * 0.25, height: h * 0.18).rotationEffect(.degrees(-15)).position(x: w * 0.34, y: h * 0.42)
                Ellipse().fill(Color.black).frame(width: w * 0.25, height: h * 0.18).rotationEffect(.degrees(15)).position(x: w * 0.66, y: h * 0.42)
                Circle().fill(Color.white).frame(width: w * 0.08).position(x: w * 0.36, y: h * 0.42)
                Circle().fill(Color.white).frame(width: w * 0.08).position(x: w * 0.64, y: h * 0.42)
                Ellipse().fill(Color.black).frame(width: w * 0.1, height: h * 0.06).position(x: w/2, y: h * 0.6)
            }
        }
    }
}

struct RedPandaFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#DC2626")).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                Circle().fill(Color(hex: "#DC2626")).frame(width: w * 0.18).position(x: w * 0.22, y: h * 0.18)
                Circle().fill(Color(hex: "#DC2626")).frame(width: w * 0.18).position(x: w * 0.78, y: h * 0.18)
                Ellipse().fill(Color.white).frame(width: w * 0.22, height: h * 0.12).position(x: w * 0.34, y: h * 0.42)
                Ellipse().fill(Color.white).frame(width: w * 0.22, height: h * 0.12).position(x: w * 0.66, y: h * 0.42)
                Circle().fill(Color.black).frame(width: w * 0.08).position(x: w * 0.36, y: h * 0.42)
                Circle().fill(Color.black).frame(width: w * 0.08).position(x: w * 0.64, y: h * 0.42)
                Ellipse().fill(Color.black).frame(width: w * 0.08, height: h * 0.05).position(x: w/2, y: h * 0.58)
            }
        }
    }
}

struct PangolinFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#A8A29E")).frame(width: w * 0.9, height: h * 0.85).position(x: w/2, y: h/2)
                ForEach(0..<9, id: \.self) { i in
                    Ellipse().fill(Color(hex: "#78716C")).frame(width: w * 0.15, height: h * 0.1)
                        .position(x: w * (0.25 + CGFloat(i % 3) * 0.25), y: h * (0.32 + CGFloat(i / 3) * 0.15))
                }
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.38, y: h * 0.38)
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.62, y: h * 0.38)
                Ellipse().fill(Color(hex: "#D6D3D1")).frame(width: w * 0.22, height: h * 0.12).position(x: w/2, y: h * 0.7)
            }
        }
    }
}

struct SalamanderFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color(hex: "#854D0E")).frame(width: w * 0.9, height: h * 0.68).position(x: w/2, y: h/2)
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Color(hex: "#FDE047")).frame(width: w * 0.08)
                        .position(x: w * (0.28 + CGFloat(i % 2) * 0.44), y: h * (0.38 + CGFloat(i / 2) * 0.22))
                }
                Circle().fill(Color.white).frame(width: w * 0.15).position(x: w * 0.32, y: h * 0.38)
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.34, y: h * 0.38)
                Circle().fill(Color.white).frame(width: w * 0.15).position(x: w * 0.68, y: h * 0.38)
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.66, y: h * 0.38)
            }
        }
    }
}

struct CraneFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(Color.white).frame(width: w * 0.78, height: h * 0.72).position(x: w/2, y: h/2)
                Ellipse().fill(Color(hex: "#EF4444")).frame(width: w * 0.22, height: h * 0.1).position(x: w/2, y: h * 0.22)
                Path { p in p.move(to: CGPoint(x: w * 0.38, y: h * 0.35)); p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.68)) }.stroke(Color.black, lineWidth: 3)
                Path { p in p.move(to: CGPoint(x: w * 0.62, y: h * 0.35)); p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.68)) }.stroke(Color.black, lineWidth: 3)
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.42, y: h * 0.38)
                Circle().fill(Color.black).frame(width: w * 0.06).position(x: w * 0.58, y: h * 0.38)
                Triangle().fill(Color(hex: "#F59E0B")).frame(width: w * 0.12, height: h * 0.22).position(x: w/2, y: h * 0.65)
            }
        }
    }
}

// MARK: - Helper Views
struct EyePair: View {
    let w: CGFloat, h: CGFloat
    let eyeColor: Color
    var yPos: CGFloat = 0.42
    var xSpread: CGFloat = 0.16
    var pupilColor: Color = .black
    var slitPupil: Bool = false
    
    var body: some View {
        Group {
            Ellipse().fill(Color.white).frame(width: w * 0.16, height: h * 0.12).position(x: w * (0.5 - xSpread), y: h * yPos)
            if slitPupil {
                Ellipse().fill(pupilColor).frame(width: w * 0.03, height: h * 0.08).position(x: w * (0.5 - xSpread + 0.01), y: h * yPos)
            } else {
                Circle().fill(eyeColor).frame(width: w * 0.07).position(x: w * (0.5 - xSpread + 0.01), y: h * yPos)
            }
            Ellipse().fill(Color.white).frame(width: w * 0.16, height: h * 0.12).position(x: w * (0.5 + xSpread), y: h * yPos)
            if slitPupil {
                Ellipse().fill(pupilColor).frame(width: w * 0.03, height: h * 0.08).position(x: w * (0.5 + xSpread - 0.01), y: h * yPos)
            } else {
                Circle().fill(eyeColor).frame(width: w * 0.07).position(x: w * (0.5 + xSpread - 0.01), y: h * yPos)
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            ForEach(TeamMascotType.allCases, id: \.self) { mascot in
                VStack(spacing: 6) {
                    TeamMascotLogo(mascot: mascot, size: 70)
                    Text(mascot.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}
