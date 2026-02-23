import Foundation

// MARK: - Drill Localization
/// Provides localized strings for drill content
struct DrillLocalization {
    
    // MARK: - Drill Name Translations
    static let drillNames: [String: String] = [
        // Batch 1 - Original Drills
        "2v1 Shooting": "二打一投篮",
        "Pit Stop 3s": "进站三分",
        "100 Makes": "百球命中",
        "Swish": "空心球",
        "Spread 5 Shooting": "五点扩展投篮",
        "Spread 3 Shooting": "三点扩展投篮",
        "Catch and Shoot on the Move": "移动接球投篮",
        "Wing Shooting with Pivots": "侧翼转身投篮",
        "2 Ball Pound and Shoot": "双球拍地投篮",
        "Form Shooting Circuit": "投篮姿势训练",
        "Paint Touch Finishing": "禁区触球终结",
        "Cone Finishing": "锥桶终结训练",
        "Mikan Drill": "米坎训练",
        "Reverse Mikan": "反向米坎",
        "Floater Circuit": "抛投训练",
        "Euro Step Series": "欧洲步系列",
        "Post Moves Circuit": "低位技术训练",
        "2 Ball Stationary": "双球静态运球",
        "2 Ball Walking": "双球行进运球",
        "Tennis Ball Dribbling": "网球运球训练",
        "Figure 8 Dribbling": "八字运球",
        "Full Court Speed Dribble": "全场速度运球",
        "Cone Weave Dribbling": "锥桶穿梭运球",
        "Defensive Slides": "防守滑步",
        "Closeout Drill": "封堵训练",
        "Shell Drill": "壳式防守训练",
        "Chair 1v1": "椅子一对一",
        
        // Batch 2 - Shooting & Skills
        "Partner Shooting": "双人投篮",
        "20 Shooting": "二十球投篮",
        "14 in :90": "90秒14球",
        "Big Shot": "大投篮",
        "Nuggets Drill": "掘金队训练",
        "Arc Finishing": "弧线终结",
        "1v1 Cone Touch": "触锥一对一",
        "Euro Step Drill": "欧洲步训练",
        "Baseline Drive Team Shooting": "底线突破团队投篮",
        "Drag Screen Team Shooting": "拖拽掩护团队投篮",
        "Pistol Action Team Shooting": "手枪战术团队投篮",
        "Post Entry Team Shooting": "低位进攻团队投篮",
        "DHO Reject Team Shooting": "拒绝手递手团队投篮",
        
        // Batch 2 - Defense
        "1 on 1 Closeout": "一对一封堵",
        "Man In The Hole": "坑中人",
        "1v1 to 3v3 Full Court": "全场一对一到三对三",
        "4v4 Shell Drill": "四对四壳式训练",
        "4 on 3 Overload": "四打三超载",
        "No Paint Drill": "禁区保护训练",
        "5v4 Whistle Change": "五对四哨响换人",
        "4v4 With Baseline Drivers": "四对四底线突破",
        "5v2 Weak Side Help": "五对二弱侧协防",
        "Complete Man To Man Drill": "完整盯人训练",
        "2 on 2 Ball Screens": "二对二挡拆",
        "B.U. Closeouts": "波士顿大学封堵",
        "2v2 Shell": "二对二壳式训练",
        "Deflection Drill": "抢断训练",
        
        // Batch 3 - Press Defense
        "Get Back Drill": "回防训练",
        "1v2 Trapping": "一对二夹击",
        "3v2 Sideline Trap": "三对二边线夹击",
        "2v1 Tip From Behind": "二对一背后拍球",
        "Trap To A Tip": "夹击到拍球",
        "Tip From Behind": "背后拍球",
        "Split & Tip": "突破与拍球",
        "4v4 Box Middle Drill": "四对四中路盒式训练",
        "4v4 Box Sideline Drill": "四对四边线盒式训练",
        "Guard Overload": "后卫超载",
        "Rebound By Numbers": "按号篮板",
        
        // Batch 3 - Offense
        "Curl Cut Drill": "绕切训练",
        "Flare Cut Drill": "向外切训练",
        "Kick Up Drill": "踢球向上训练",
        "Kick Back Drill": "踢球回传训练",
        "2 Man Hammer Pass": "双人锤子传球",
        "Handoff & Help Drill": "手递手与协防训练",
        "Zoom Reads Drill": "快速阅读训练",
        "Press Breaker Drill": "破紧逼训练"
    ]
    
    // MARK: - Category Translations
    static let categoryNames: [String: String] = [
        "shooting": "投篮",
        "offense": "进攻",
        "defense": "防守",
        "skills": "技术",
        "conditioning": "体能",
        "warmup": "热身",
        "cooldown": "放松"
    ]
    
    // MARK: - Difficulty Translations
    static let difficultyNames: [String: String] = [
        "beginner": "初级",
        "intermediate": "中级",
        "advanced": "高级"
    ]
    
    // MARK: - UI String Translations
    static let uiStrings: [String: String] = [
        // Headers
        "Drills": "训练库",
        "Drill Library": "训练库",
        "Search drills...": "搜索训练...",
        "All": "全部",
        "Favorites": "收藏",
        
        // Empty States
        "No drills yet": "暂无训练",
        "Add your first drill to get started": "添加第一个训练开始",
        "Try adjusting your filters": "尝试调整筛选条件",
        "Add Drill": "添加训练",
        "Clear Filters": "清除筛选",
        
        // Detail View
        "Description": "描述",
        "Instructions": "步骤",
        "Key Points": "要点",
        "Equipment Needed": "所需器材",
        "Variations": "变化",
        "Players": "人数",
        "Duration": "时长",
        "min": "分钟",
        "minutes": "分钟",
        
        // Categories Section
        "Featured Drills": "精选训练",
        "Quick Drills": "快速训练",
        "Team Drills": "团队训练",
        "Individual Drills": "个人训练",
        "Browse by Category": "按类别浏览",
        "Recent Drills": "最近使用",
        "Popular": "热门",
        
        // Stats
        "Total Drills": "训练总数",
        "Categories": "类别",
        "Difficulty Levels": "难度等级",
        
        // Actions
        "Start Drill": "开始训练",
        "Add to Session": "添加到课程",
        "Share": "分享",
        "Edit": "编辑",
        "Delete": "删除",
        
        // Form
        "Basic Info": "基本信息",
        "Drill Name": "训练名称",
        "Category": "类别",
        "Difficulty": "难度",
        "New Drill": "新训练",
        "Edit Drill": "编辑训练",
        "Cancel": "取消",
        "Save": "保存",
        "Create": "创建",
        "Step": "步骤",
        "Point": "要点",
        "Add Step": "添加步骤",
        "Add Point": "添加要点",
        "Min Players": "最少人数"
    ]
    
    // MARK: - Equipment Translations
    static let equipmentNames: [String: String] = [
        "Basketball": "篮球",
        "2 Basketballs": "2个篮球",
        "3 Basketballs": "3个篮球",
        "Cones": "锥桶",
        "5 Cones": "5个锥桶",
        "2 Cones": "2个锥桶",
        "Chair": "椅子",
        "2 Chairs": "2把椅子",
        "3 Chairs": "3把椅子",
        "Tennis Ball": "网球",
        "Resistance Band": "阻力带",
        "Medicine Ball": "药球",
        "Ladder": "敏捷梯",
        "Hurdles": "跨栏",
        "Shooting Machine": "投篮机",
        "Pad": "护垫"
    ]
    
    // MARK: - Helper Methods
    static func localizedDrillName(_ name: String) -> String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return drillNames[name] ?? name
        }
        return name
    }
    
    static func localizedCategory(_ category: DrillCategory) -> String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return categoryNames[category.rawValue] ?? category.displayName
        }
        return category.displayName
    }
    
    static func localizedDifficulty(_ difficulty: DifficultyLevel) -> String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return difficultyNames[difficulty.rawValue] ?? difficulty.displayName
        }
        return difficulty.displayName
    }
    
    static func localizedEquipment(_ equipment: String) -> String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return equipmentNames[equipment] ?? equipment
        }
        return equipment
    }
    
    static func localizedString(_ key: String) -> String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return uiStrings[key] ?? key
        }
        return key
    }
    
    /// Shorthand for localized string
    static func L(_ key: String) -> String {
        localizedString(key)
    }
}

// MARK: - DrillItem Extension for Localization
extension DrillItem {
    var localizedName: String {
        DrillLocalization.localizedDrillName(name)
    }
    
    var localizedCategory: String {
        DrillLocalization.localizedCategory(category)
    }
    
    var localizedDifficulty: String {
        DrillLocalization.localizedDifficulty(difficulty)
    }
    
    var localizedEquipment: [String] {
        equipmentNeeded.map { DrillLocalization.localizedEquipment($0) }
    }
    
    var localizedPlayerRange: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        if let max = maxPlayers {
            return isChinese ? "\(minPlayers)-\(max)人" : "\(minPlayers)-\(max) players"
        }
        return isChinese ? "\(minPlayers)+人" : "\(minPlayers)+ players"
    }
    
    var localizedDuration: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return isChinese ? "\(durationMinutes)分钟" : "\(durationMinutes) min"
    }
}

// MARK: - DrillCategory Extension for Localization
extension DrillCategory {
    var localizedName: String {
        DrillLocalization.localizedCategory(self)
    }
}

// MARK: - DifficultyLevel Extension for Localization  
extension DifficultyLevel {
    var localizedName: String {
        DrillLocalization.localizedDifficulty(self)
    }
}

// MARK: - Drill Content Localization
/// Aggregates all drill content translations from batch files
/// Syncs with Supabase drill names as keys
struct DrillContentLocalization {
    
    // MARK: - Aggregated Descriptions
    static var descriptions: [String: String] {
        var all: [String: String] = [:]
        all.merge(DrillContentBatch1.descriptions) { _, new in new }
        all.merge(DrillContentBatch2.descriptions) { _, new in new }
        all.merge(DrillContentBatch3.descriptions) { _, new in new }
        all.merge(DrillContentBatch4.descriptions) { _, new in new }
        all.merge(DrillContentBatch5.descriptions) { _, new in new }
        all.merge(DrillContentBatch5.additionalDescriptions) { _, new in new }
        return all
    }
    
    // MARK: - Aggregated Instructions
    static var instructions: [String: [String]] {
        var all: [String: [String]] = [:]
        all.merge(DrillContentBatch1.instructions) { _, new in new }
        all.merge(DrillContentBatch2.instructions) { _, new in new }
        all.merge(DrillContentBatch3.instructions) { _, new in new }
        all.merge(DrillContentBatch4.instructions) { _, new in new }
        all.merge(DrillContentBatch5.instructions) { _, new in new }
        all.merge(DrillContentBatch5.additionalInstructions) { _, new in new }
        return all
    }
    
    // MARK: - Aggregated Key Points
    static var keyPoints: [String: [String]] {
        var all: [String: [String]] = [:]
        all.merge(DrillContentBatch1.keyPoints) { _, new in new }
        all.merge(DrillContentBatch2.keyPoints) { _, new in new }
        all.merge(DrillContentBatch3.keyPoints) { _, new in new }
        all.merge(DrillContentBatch4.keyPoints) { _, new in new }
        all.merge(DrillContentBatch5.keyPoints) { _, new in new }
        all.merge(DrillContentBatch5.additionalKeyPoints) { _, new in new }
        return all
    }
    
    // MARK: - Aggregated Variations
    static var variations: [String: [String]] {
        var all: [String: [String]] = [:]
        all.merge(DrillContentBatch1.variations) { _, new in new }
        all.merge(DrillContentBatch2.variations) { _, new in new }
        all.merge(DrillContentBatch3.variations) { _, new in new }
        all.merge(DrillContentBatch4.variations) { _, new in new }
        all.merge(DrillContentBatch5.variations) { _, new in new }
        all.merge(DrillContentBatch5.additionalVariations) { _, new in new }
        return all
    }
    
    // MARK: - Helper Methods
    
    /// Get localized description for a drill by name
    static func localizedDescription(for drillName: String) -> String? {
        guard LocalizationManager.shared.currentLanguage == .chinese else { return nil }
        return descriptions[drillName]
    }
    
    /// Get localized instructions for a drill by name
    static func localizedInstructions(for drillName: String) -> [String]? {
        guard LocalizationManager.shared.currentLanguage == .chinese else { return nil }
        return instructions[drillName]
    }
    
    /// Get localized key points for a drill by name
    static func localizedKeyPoints(for drillName: String) -> [String]? {
        guard LocalizationManager.shared.currentLanguage == .chinese else { return nil }
        return keyPoints[drillName]
    }
    
    /// Get localized variations for a drill by name
    static func localizedVariations(for drillName: String) -> [String]? {
        guard LocalizationManager.shared.currentLanguage == .chinese else { return nil }
        return variations[drillName]
    }
}

// MARK: - DrillItem Content Localization Extension
extension DrillItem {
    
    /// Localized description - falls back to original if no translation
    var localizedDescription: String {
        DrillContentLocalization.localizedDescription(for: name) ?? description
    }
    
    /// Localized instructions - falls back to original if no translation
    var localizedInstructions: [String] {
        DrillContentLocalization.localizedInstructions(for: name) ?? instructions
    }
    
    /// Localized key points - falls back to original if no translation
    var localizedKeyPoints: [String] {
        DrillContentLocalization.localizedKeyPoints(for: name) ?? keyPoints
    }
    
    /// Localized variations - falls back to original if no translation
    var localizedVariations: [String] {
        DrillContentLocalization.localizedVariations(for: name) ?? variations
    }
}
