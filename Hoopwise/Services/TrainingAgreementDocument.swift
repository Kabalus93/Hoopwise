import Foundation
import CoreGraphics

/// Bilingual private training service agreement.
///
/// The clause text is the coach's, supplied verbatim, and MUST NOT be edited,
/// paraphrased, translated, or "improved" by anyone maintaining this file. It is
/// the operative wording of a contract with real clients. Field values are
/// substituted into the tokens; the prose around them is fixed.
///
/// Chinese precedes English within every clause, because that is the language
/// the clients read. Clause 9 makes the Chinese text prevailing, which is
/// deliberate — do not remove it.
enum TrainingAgreementDocument {

    /// Every substitutable value. Anything unknown renders as a fill-in rule
    /// rather than a wrong value, so the coach can complete it by hand.
    struct Fields {
        var coachName: String = ""
        var studentNameZh: String = ""
        var studentNameEn: String = ""
        var guardianName: String = ""
        var guardianRelation: String = ""
        var clientContact: String = ""
        var bundleSize: String = ""
        var sessionMinutes: String = ""
        var currency: String = ""
        var pricePerSession: String = ""
        var bundleTotal: String = ""
        var travelFee: String = ""
        var travelFeeBasis: String = ""
        var amountPaid: String = ""
        var startDate: String = ""
        var validityMonths: String = ""

        /// Clause 8 consent. `nil` renders empty boxes for signing; a value
        /// renders the stored state. Currently always nil — the contract has no
        /// consent columns yet.
        var consentCoachingAnalysis: Bool? = nil
        var consentPublicPublication: Bool? = nil
    }

    // MARK: - Field Resolution

    @MainActor
    static func makeFields(studentId: UUID,
                           contract: Contract,
                           dataManager: SwiftDataManager) -> Fields {
        var fields = Fields()
        fields.coachName = dataManager.coach.name

        if let student = dataManager.students.first(where: { $0.id == studentId }) {
            fields.studentNameZh = student.chineseName ?? ""
            fields.studentNameEn = student.name
        }

        // Guardian details live on Player, not Student.
        if let player = dataManager.player(for: studentId) {
            fields.guardianName = player.parentInfo.name
            fields.guardianRelation = player.parentInfo.relationship
            let contacts = [player.parentInfo.phone, player.parentInfo.wechatId]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            fields.clientContact = contacts.joined(separator: " / ")
        }

        let code = dataManager.appSettings.currency.currencyCode
        fields.currency = currencySymbol(for: code)
        fields.bundleSize = contract.bundleSize > 0 ? "\(contract.bundleSize)" : ""
        fields.pricePerSession = decimal(contract.pricePerSession)
        fields.bundleTotal = decimal(contract.bundleAmount)
        fields.amountPaid = decimal(contract.amountPaid)

        if contract.hasTravelFee {
            fields.travelFee = decimal(contract.travelFeeAmount)
            fields.travelFeeBasis = contract.travelFeeBasis == .perContract
                ? "每份合同 per contract"
                : "每节课 per session"
        }

        fields.startDate = dateString(contract.enrollmentDate)

        // sessionMinutes and validityMonths have no home on Contract yet, so
        // they stay blank and print as a rule to complete by hand.
        return fields
    }

    /// `Agreement_<name>_Contract<N>_<yyyy-MM-dd>.pdf`, matching the statement
    /// convention so both documents for a client file together.
    static func filename(for fields: Fields, contractNumber: Int) -> String {
        let name = (fields.studentNameZh.isEmpty ? fields.studentNameEn : fields.studentNameZh)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "Agreement_\(name)_Contract\(contractNumber)_\(formatter.string(from: Date()))"
    }

    // MARK: - Render

    @discardableResult
    static func render(_ fields: Fields, contractNumber: Int, to url: URL? = nil) throws -> URL {
        let renderer = PDFDocumentRenderer()
        renderer.onPageBegin = { doc, page in
            doc.footer("私人篮球训练服务协议 · Private Basketball Training Service Agreement · 第 \(page) 页 / Page \(page)")
        }

        let body: (PDFDocumentRenderer) -> Void = { doc in
            doc.text("私人篮球训练服务协议", style: .title(19))
            doc.text("Private Basketball Training Service Agreement", style: .heading(12.5))
            doc.spacer(8)
            doc.rule()
            doc.spacer(12)

            parties(doc, fields)
            sessionsAndFees(doc, fields)
            validity(doc, fields)
            scheduling(doc)
            coachCancellation(doc)
            refunds(doc)
            healthAndRisk(doc)
            imageUse(doc, fields)
            general(doc)
            signatures(doc, fields)
        }

        if let url {
            return try renderer.render(to: url, body)
        }
        return try renderer.renderToTemporaryFile(named: filename(for: fields, contractNumber: contractNumber), body)
    }

    // MARK: - Clauses
    //
    // Wording is verbatim from the coach. Do not alter.

    private static func clauseHeading(_ doc: PDFDocumentRenderer, _ text: String) {
        doc.ensureSpace(46)
        doc.spacer(6)
        doc.text(text, style: .heading(12))
        doc.spacer(4)
    }

    private static func parties(_ doc: PDFDocumentRenderer, _ f: Fields) {
        clauseHeading(doc, "1. 双方信息 / Parties")
        doc.text("教练（甲方）：\(fill(f.coachName))", style: .body())
        doc.text("学员（乙方）：\(fill(f.studentNameZh)) / \(fill(f.studentNameEn))", style: .body())
        doc.text("监护人（如学员为未成年人）：\(fill(f.guardianName))，与学员关系：\(fill(f.guardianRelation))", style: .body())
        doc.text("联系方式：\(fill(f.clientContact))", style: .body())
        doc.spacer(5)
        doc.text("Coach (Party A): \(fill(f.coachName))", style: .body())
        doc.text("Student (Party B): \(fill(f.studentNameZh)) / \(fill(f.studentNameEn))", style: .body())
        doc.text("Guardian, where the student is a minor: \(fill(f.guardianName)), relationship: \(fill(f.guardianRelation))", style: .body())
        doc.text("Contact: \(fill(f.clientContact))", style: .body())
    }

    private static func sessionsAndFees(_ doc: PDFDocumentRenderer, _ f: Fields) {
        clauseHeading(doc, "2. 课时与费用 / Sessions and Fees")
        doc.text("乙方购买课时 \(fill(f.bundleSize)) 节，每节 \(fill(f.sessionMinutes)) 分钟，单价 \(f.currency)\(fill(f.pricePerSession))，合计 \(f.currency)\(fill(f.bundleTotal))。交通补贴 \(f.currency)\(fill(f.travelFee))（\(fill(f.travelFeeBasis))），如适用。已付金额 \(f.currency)\(fill(f.amountPaid))。",
                 style: .body())
        doc.spacer(5)
        doc.text("Party B purchases \(fill(f.bundleSize)) sessions of \(fill(f.sessionMinutes)) minutes each at \(f.currency)\(fill(f.pricePerSession)) per session, totalling \(f.currency)\(fill(f.bundleTotal)). Travel allowance \(f.currency)\(fill(f.travelFee)) (\(fill(f.travelFeeBasis))) where applicable. Amount paid: \(f.currency)\(fill(f.amountPaid)).",
                 style: .body())
    }

    private static func validity(_ doc: PDFDocumentRenderer, _ f: Fields) {
        clauseHeading(doc, "3. 有效期 / Validity Period")
        doc.text("本协议自 \(fill(f.startDate)) 起，有效期 \(fill(f.validityMonths)) 个月。逾期未使用的课时，经双方协商可延期。",
                 style: .body())
        doc.spacer(5)
        doc.text("This agreement takes effect on \(fill(f.startDate)) and is valid for \(fill(f.validityMonths)) months. Unused sessions beyond that date may be extended by mutual agreement.",
                 style: .body())
    }

    private static func scheduling(_ doc: PDFDocumentRenderer) {
        clauseHeading(doc, "4. 时间安排与请假 / Scheduling and Cancellation")
        doc.text("课程时间与地点由双方提前约定。乙方如需请假，应至少提前 24 小时通知，课时不予扣除。不足 24 小时通知或未到场，视为已消课。",
                 style: .body())
        doc.spacer(5)
        doc.text("Session times and locations are agreed in advance. Party B may cancel with at least 24 hours' notice without deduction. Cancellation within 24 hours, or non-attendance, consumes the session.",
                 style: .body())
    }

    private static func coachCancellation(_ doc: PDFDocumentRenderer) {
        clauseHeading(doc, "5. 甲方取消与不可控因素 / Coach Cancellation and Uncontrollable Factors")
        doc.text("甲方因故取消课程，或因场地关闭、恶劣天气等不可控因素无法进行的课程，另行安排补课，不扣除课时。",
                 style: .body())
        doc.spacer(5)
        doc.text("Sessions cancelled by Party A, or prevented by venue closure, severe weather, or other factors outside either party's control, are rescheduled without deduction.",
                 style: .body())
    }

    private static func refunds(_ doc: PDFDocumentRenderer) {
        clauseHeading(doc, "6. 退款 / Refunds")
        doc.text("乙方如需终止本协议，未消耗课时按原单价全额退还，已消耗课时不予退还。", style: .body())
        doc.spacer(5)
        doc.text("Should Party B terminate this agreement, unused sessions are refunded in full at the stated unit price. Consumed sessions are not refundable.",
                 style: .body())
    }

    private static func healthAndRisk(_ doc: PDFDocumentRenderer) {
        clauseHeading(doc, "7. 健康与风险 / Health and Risk")
        doc.text("乙方确认学员身体状况适合参加篮球训练，并已如实告知相关病史、伤情或用药情况。乙方理解体育训练存在一般运动风险。",
                 style: .body())
        doc.spacer(5)
        doc.text("Party B confirms the student is medically fit for basketball training and has disclosed any relevant medical history, injury, or medication. Party B understands that athletic training carries ordinary risk of injury.",
                 style: .body())
    }

    private static func imageUse(_ doc: PDFDocumentRenderer, _ f: Fields) {
        clauseHeading(doc, "8. 肖像与影像使用 / Image and Video Use")
        doc.text("甲方可能在训练中拍摄照片或视频。用途分为两项，须分别授权：", style: .body())
        doc.spacer(3)
        doc.text("（一）教学分析（仅供甲方与乙方内部使用）：\(checkbox(f.consentCoachingAnalysis, positive: true)) 同意  \(checkbox(f.consentCoachingAnalysis, positive: false)) 不同意",
                 style: .body(), indent: 12)
        doc.text("（二）公开发布（社交媒体、教学内容等）：\(checkbox(f.consentPublicPublication, positive: true)) 同意  \(checkbox(f.consentPublicPublication, positive: false)) 不同意",
                 style: .body(), indent: 12)
        doc.spacer(3)
        doc.text("乙方可随时以书面方式撤回上述任一授权。", style: .body())
        doc.spacer(5)
        doc.text("Party A may photograph or record video during training. The two purposes require separate consent:",
                 style: .body())
        doc.spacer(3)
        doc.text("(a) Coaching analysis, used only between Party A and Party B:  \(asciiBox(f.consentCoachingAnalysis, positive: true)) Consent  \(asciiBox(f.consentCoachingAnalysis, positive: false)) Do not consent",
                 style: .body(), indent: 12)
        doc.text("(b) Public publication, including social media and instructional content:  \(asciiBox(f.consentPublicPublication, positive: true)) Consent  \(asciiBox(f.consentPublicPublication, positive: false)) Do not consent",
                 style: .body(), indent: 12)
        doc.spacer(3)
        doc.text("Party B may withdraw either consent in writing at any time.", style: .body())
    }

    private static func general(_ doc: PDFDocumentRenderer) {
        clauseHeading(doc, "9. 其他 / General")
        doc.text("本协议的任何变更须经双方书面确认。本协议以中英文书写，如两种文本存在歧义，以中文文本为准。",
                 style: .body())
        doc.spacer(5)
        doc.text("Any amendment requires written confirmation from both parties. This agreement is written in Chinese and English; in the event of any discrepancy, the Chinese text prevails.",
                 style: .body())
    }

    private static func signatures(_ doc: PDFDocumentRenderer, _ f: Fields) {
        // Signatures must not straddle a page break.
        doc.ensureSpace(150)
        clauseHeading(doc, "10. 签署 / Signatures")
        doc.spacer(10)
        doc.text("甲方签字 Party A: ____________________        日期 Date: ______________", style: .body())
        doc.spacer(18)
        doc.text("乙方签字 Party B: ____________________        日期 Date: ______________", style: .body())
        doc.spacer(18)
        doc.text("学员姓名（正楷）Student name (printed): \(fill(f.studentNameZh, width: 24))", style: .body())
    }

    // MARK: - Formatting

    /// Unknown values print as a rule to complete by hand. Never substitute a
    /// plausible-looking default into a contract.
    private static func fill(_ value: String, width: Int = 16) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(repeating: "_", count: width) : trimmed
    }

    /// Chinese checkbox. Empty when consent is unrecorded, so a fresh agreement
    /// prints blank boxes to tick by hand.
    private static func checkbox(_ state: Bool?, positive: Bool) -> String {
        guard let state else { return "□" }
        return state == positive ? "☑" : "□"
    }

    private static func asciiBox(_ state: Bool?, positive: Bool) -> String {
        guard let state else { return "[  ]" }
        return state == positive ? "[X]" : "[  ]"
    }

    private static func currencySymbol(for code: String) -> String {
        switch code {
        case "CNY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default:    return code + " "
        }
    }

    private static func decimal(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
