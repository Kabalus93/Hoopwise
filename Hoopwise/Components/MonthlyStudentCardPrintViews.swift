import SwiftUI

extension ReportLocalization {
    var playerFileTitle: String { isChinese ? "球员档案" : "PLAYER FILE" }
    var performanceTitle: String { isChinese ? "表现分析" : "PERFORMANCE" }

    func performanceDescription(_ index: Int) -> String {
        let en = [
            "Shot making and finishing",
            "Passing and creating for others",
            "Winning the ball after misses",
            "Stops, steals and blocks",
            "Speed, balance and explosiveness",
            "Hustle and overall involvement"
        ]
        let cn = [
            "投篮与终结能力",
            "传球与带动队友",
            "争抢篮板能力",
            "防守、抢断与盖帽",
            "速度、平衡与爆发力",
            "积极性与场上投入"
        ]
        return isChinese ? cn[index] : en[index]
    }
}

struct StudentCollectibleCardFrontView: View {
    static let baseSize = CGSize(width: 380, height: 516)
    private static let topSectionHeight: CGFloat = 204

    let snapshot: MonthlyStudentCardSnapshot

    private let loc = ReportLocalization()
    private let cardBackground = Color(hex: "#F5F0E6")
    private let cardBorder = Color(hex: "#8B7355")

    private var accent: Color { Color.avatarColor(snapshot.student.avatarColor) }

    var body: some View {
        VStack(spacing: 0) {
            topSection
            middleSection
            statsGridCard
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height, alignment: .top)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorder, lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    private var topSection: some View {
        ZStack(alignment: .top) {
            topBackground

            HStack(alignment: .top) {
                headerLogoView
                Spacer()
                headerMonthView
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            VStack(spacing: 2) {
                if snapshot.primaryCardNameIsLatin {
                    Text(snapshot.primaryCardName.uppercased())
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.white)
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                } else {
                    Text(snapshot.primaryCardName)
                        .font(.system(size: 50, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                if let secondary = snapshot.secondaryCardName {
                    Text(snapshot.primaryCardNameIsLatin ? secondary : secondary.uppercased())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .tracking(snapshot.primaryCardNameIsLatin ? 0 : 1)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.top, 56)
            .padding(.horizontal, 36)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.baseSize.width, height: Self.topSectionHeight)
        .clipped()
    }

    private var topBackground: some View {
        Group {
            if let image = snapshot.backgroundImage {
                PlatformCardImageView(image: image)
                    .blur(radius: 4)
                    .frame(width: Self.baseSize.width + 32, height: Self.topSectionHeight + 32)
                    .offset(y: -16)
            } else {
                Color(hex: "#3a2a1a").opacity(0.85)
            }
        }
        .frame(width: Self.baseSize.width, height: Self.topSectionHeight)
        .clipped()
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.5), .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var middleSection: some View {
        ZStack(alignment: .top) {
            profilePhotoView
                .offset(y: -64)

            VStack(spacing: 0) {
                Spacer()
                frontDetailsStrip
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 126)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var profilePhotoView: some View {
        ZStack {
            Circle().fill(.white).frame(width: 158, height: 158)
            Circle().stroke(cardBorder, lineWidth: 3).frame(width: 148, height: 148)

            if let image = snapshot.profileImage {
                PlatformCardImageView(image: image)
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
            } else {
                Circle().fill(accent).frame(width: 140, height: 140)
                Text(snapshot.student.initials)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }

    private var headerLogoView: some View {
        Color.white
            .mask(
                Image("KuxunLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 164, height: 36, alignment: .leading)
            )
            .frame(width: 164, height: 36, alignment: .leading)
            .frame(maxWidth: 164, alignment: .leading)
    }

    private var headerMonthView: some View {
        Text(snapshot.monthLabel)
            .font(.system(size: 31, weight: .heavy))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 76, height: 36, alignment: .trailing)
    }

    private var jerseyBadgeView: some View {
        ZStack {
            if let jerseyNumber = snapshot.player?.jerseyNumber {
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 44, height: 44)
                Text("\(jerseyNumber)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 44, height: 44, alignment: .leading)
    }

    private var frontDetailsStrip: some View {
        HStack(spacing: 0) {
            frontDetailCell(label: loc.isChinese ? "年级" : "GRD", value: snapshot.student.schoolGrade?.localizedShortName ?? "—")
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: 34)
            frontDetailCell(label: loc.isChinese ? "身高" : "HT", value: snapshot.heightString)
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 1, height: 34)
            frontDetailCell(label: loc.isChinese ? "手" : "HAND", value: snapshot.handednessString(loc: loc))
        }
    }

    private func frontDetailCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }

    private var statsGridCard: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
            HStack(spacing: 0) {
                statCell(snapshot.formatStat(snapshot.trainingStats.ppg), label: loc.ppgLabel, metric: .ppg)
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)
                statCell(snapshot.formatStat(snapshot.trainingStats.apg), label: loc.apgLabel, metric: .apg)
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)
                statCell(snapshot.formatStat(snapshot.trainingStats.rpg), label: loc.rpgLabel, metric: .rpg)
            }
            .frame(height: 80)
            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
            HStack(spacing: 0) {
                statCell(snapshot.formatStat(snapshot.trainingStats.spg), label: loc.stlLabel, metric: .spg)
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)
                statCell(snapshot.formatStat(snapshot.trainingStats.bpg), label: loc.blkLabel, metric: .bpg)
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)
                statCell(snapshot.effortString, label: loc.effLabel, metric: .effort)
            }
            .frame(height: 80)
        }
        .padding(.top, 12)
        .padding(.bottom, 0)
    }

    private func statCell(_ value: String, label: String, metric: MonthlyStudentCardSnapshot.TrendMetric) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black.opacity(0.72))
            Text(snapshot.deltaText(for: metric, loc: loc))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(deltaColor(for: metric))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func deltaColor(for metric: MonthlyStudentCardSnapshot.TrendMetric) -> Color {
        guard let delta = snapshot.deltaValue(for: metric) else { return .gray }
        switch delta {
        case let value where value > 0.05:
            return Color.green.opacity(0.85)
        case let value where value < -0.05:
            return Color.red.opacity(0.8)
        default:
            return .gray
        }
    }
}

struct StudentCollectibleCardBackView: View {
    static let baseSize = StudentCollectibleCardFrontView.baseSize

    let snapshot: MonthlyStudentCardSnapshot

    private let loc = ReportLocalization()
    private let cardBackground = Color(hex: "#F5F0E6")
    private let cardBorder = Color(hex: "#8B7355")
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text(loc.playerFileTitle)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.black)
                    .tracking(loc.isChinese ? 0 : 1)
                    .padding(.top, 18)

                PerformanceRadarChartView(metrics: snapshot.performanceMetrics, accentColor: snapshot.accentColor, loc: loc, isLightMode: true)
                    .frame(height: 244)
                    .padding(.horizontal, 30)
                    .padding(.top, 24)

                Text(snapshot.gamesSummaryText(loc: loc))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.top, 8)

                performanceInsightsPanel
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                Spacer(minLength: 14)
            }

            backCornerLogoView
                .padding(.top, 16)
                .padding(.trailing, 18)
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height, alignment: .top)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorder, lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    private var backCornerLogoView: some View {
        Image("HoopwiseLogoWhite")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 110, height: 24, alignment: .trailing)
            .opacity(0.62)
    }

    private var performanceInsightsPanel: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black.opacity(0.08))
            .overlay(
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc.performanceLabel(index))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Text(loc.performanceDescription(index))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.black.opacity(0.72))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            )
            .frame(height: 136)
    }
}

struct MonthlyStudentCardPDFPageView: View {
    let snapshots: [MonthlyStudentCardSnapshot]
    let side: StudentCardPageSide
    let pageSize: CGSize
    let cardSize: CGSize
    let pageMargin: CGFloat
    let interItemSpacing: CGFloat
    let rows: Int
    let columns: Int

    var body: some View {
        ZStack {
            Color.white

            VStack(spacing: interItemSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: interItemSpacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let visualColumn = side == .back ? (columns - 1 - column) : column
                            let index = row * columns + visualColumn
                            cardView(at: index)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(pageMargin)
        }
        .background(Color.white)
    }

    @ViewBuilder
    private func cardView(at index: Int) -> some View {
        if index < snapshots.count {
            let snapshot = snapshots[index]
            Group {
                switch side {
                case .front:
                    StudentCollectibleCardFrontView(snapshot: snapshot)
                case .back:
                    StudentCollectibleCardBackView(snapshot: snapshot)
                }
            }
            .scaleEffect(cardSize.width / StudentCollectibleCardFrontView.baseSize.width)
            .frame(width: cardSize.width, height: cardSize.height)
        } else {
            Color.clear
                .frame(width: cardSize.width, height: cardSize.height)
        }
    }
}

private struct PlatformCardImageView: View {
    let image: CacheImage

    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #endif
    }
}
