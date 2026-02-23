import Foundation

// MARK: - Drill Content Localization Batch 1
// Contains Chinese translations for drills 1-15 (Basic & Shooting drills)
// Syncs with Supabase drill names as keys

struct DrillContentBatch1 {
    
    // MARK: - Descriptions
    static let descriptions: [String: String] = [
        "Form Shooting": "近距离投篮训练，专注于正确的投篮姿势",
        "Spot Shooting": "在弧线周围5个点位进行投篮训练",
        "Stationary Dribbling": "静态运球基本动作训练",
        "Defensive Slides": "横向移动和防守站位训练",
        "3-Man Weave": "经典的传球和跑动训练",
        "Pick and Roll": "双人挡拆配合执行训练",
        "Suicides": "经典的篮球体能训练",
        "Dynamic Stretching": "全身动态热身训练",
        "2v1 Shooting": "二打一优势情况下的投篮或传球决策训练。球员获得比赛投篮机会，防守者练习封堵和干扰。",
        "Creighton Rebounding": "小规模篮板球比赛，培养球员强硬作风，教授各种情况下的正确卡位技术。",
        "Around The Cones Transition": "创造比赛般的转换情境，练习各种人数优势下的得分机会转化。",
        "Butler Disadvantage Drill": "4打3优势的壳式防守训练，当第四名防守者归位后转为4打4实战。",
        "4 Corners Passing": "夹击和传球训练，进攻方练习突破夹击传球，防守方练习正确的夹击技术。",
        "Marquette 3v3 Full Court": "全场3打3，强调不让中路、正确角度和人球兼顾站位。",
        "Charge To Scramble": "教授球员正确吸收进攻犯规的方法，同时制造防守轮转和混战情境。"
    ]
    
    // MARK: - Instructions
    static let instructions: [String: [String]] = [
        "Form Shooting": [
            "从距离篮筐3英尺处开始",
            "专注于BEEF原则（平衡、眼睛、手肘、跟随）",
            "投进10球后再后退"
        ],
        "Spot Shooting": [
            "5个点位：两个底角、两个侧翼、弧顶",
            "每个点位投3次",
            "记录命中数"
        ],
        "Stationary Dribbling": [
            "右手运球30秒",
            "左手运球30秒",
            "体前变向30秒",
            "胯下运球30秒"
        ],
        "Defensive Slides": [
            "从防守姿势开始",
            "从底线滑步到底线",
            "保持低重心"
        ],
        "3-Man Weave": [
            "3名球员横排站在底线",
            "传球后跑到接球人身后",
            "以上篮结束"
        ],
        "Pick and Roll": [
            "持球人发起进攻",
            "掩护人设置掩护",
            "阅读防守反应"
        ],
        "Suicides": [
            "冲刺到罚球线再返回",
            "冲刺到中场再返回",
            "全场冲刺"
        ],
        "Dynamic Stretching": [
            "高抬腿30秒",
            "后踢腿30秒",
            "腿部摆动",
            "手臂画圈"
        ],
        "2v1 Shooting": [
            "将2名进攻球员放置在场上任意位置，相隔一次传球距离",
            "1名防守球员从靠近篮筐处开始",
            "教练传球给任一进攻球员",
            "防守者封堵持球人",
            "进攻方可投篮或传球（限1次传球）",
            "防守者干扰投篮"
        ],
        "Creighton Rebounding": [
            "3名进攻球员站在外线",
            "3名防守者从禁区开始",
            "教练传球给进攻球员",
            "所有防守者封堵",
            "进攻球员立即投篮",
            "防守者必须卡位并抢下篮板"
        ],
        "Around The Cones Transition": [
            "在罚球线延长线放置3个锥桶（顶部1个，侧翼各1个）",
            "底线排成3列",
            "外侧球员持球开始",
            "所有3名球员绕过面前的锥桶冲刺",
            "绕过锥桶后进入实战"
        ],
        "Butler Disadvantage Drill": [
            "4名进攻球员站在侧翼和底角",
            "3名防守者在禁区呈三角形站位",
            "第4名防守者在中场",
            "教练传球给任一进攻球员",
            "3名防守者练习壳式轮转",
            "第4名防守者冲刺到对面底线再返回",
            "在第4名防守者归位前进攻方不能投篮，归位后进入实战"
        ],
        "4 Corners Passing": [
            "4名进攻球员呈正方形站位",
            "4名防守球员站在进攻球员之间",
            "传球开始，最近的2名防守者夹击",
            "持球进攻球员等待夹击形成",
            "其他2名防守者站在3名进攻球员之间",
            "持续30秒，统计抢断和拍球次数"
        ],
        "Marquette 3v3 Full Court": [
            "3名进攻球员横排站在底线",
            "3名防守者对位",
            "中间的进攻球员持球开始",
            "防守者迫使持球人用弱侧手向外侧运球",
            "持球人有2次运球机会突破",
            "协防者帮助后快速归位",
            "球过半场后进入3打3实战"
        ],
        "Charge To Scramble": [
            "3名进攻球员站在侧翼和弧顶",
            "防守者对位，采用不让中路姿势",
            "开始3打3对抗",
            "进攻方沿外线传球",
            "球员突破底线，对侧防守者造进攻犯规",
            "防守者倒地展示犯规",
            "进攻球员传球出去，进入实战"
        ]
    ]
    
    // MARK: - Key Points
    static let keyPoints: [String: [String]] = [
        "Form Shooting": [
            "手肘在球下方",
            "手腕下压",
            "保持跟随动作"
        ],
        "Spot Shooting": [
            "脚步一致",
            "快速出手"
        ],
        "Stationary Dribbling": [
            "眼睛抬起",
            "低运球",
            "指尖控球"
        ],
        "Defensive Slides": [
            "低姿势",
            "手要活跃",
            "脚步快速"
        ],
        "3-Man Weave": [
            "传球要干脆",
            "要有沟通"
        ],
        "Pick and Roll": [
            "掩护角度",
            "时机配合",
            "阅读并反应"
        ],
        "Suicides": [
            "触碰每条线",
            "全速冲刺"
        ],
        "Dynamic Stretching": [
            "逐渐增加强度",
            "全范围活动"
        ],
        "2v1 Shooting": [
            "强调传球及时准确",
            "进攻球员传球前先看篮筐",
            "投篮优先——防守者超过一臂距离就投篮",
            "防守者要假动作干扰接球人并把手放在传球路线上",
            "防守目标是让投篮较差的球员接受干扰投篮"
        ],
        "Creighton Rebounding": [
            "卡位技术：撞击、定位、抢篮板",
            "如果进攻球员突破你，用臀部顶住他们大腿",
            "第一次身体接触必须在禁区外完成",
            "在进阶版本中要有沟通",
            "得分的队伍留在场上"
        ],
        "Around The Cones Transition": [
            "运球者必须用内侧手保护球",
            "进攻方只有1次投篮和1次传球机会（模拟快速转换）",
            "防守者要冲到篮下阻止上篮",
            "防守者要假动作干扰运球者制造犹豫",
            "运球者进攻直到防守者挡在他和篮筐之间"
        ],
        "Butler Disadvantage Drill": [
            "强侧有人防守，弱侧1人看2个",
            "球员不应连续防守2次传球",
            "沟通必须大声、提前、持续",
            "第4名防守者归位时应补到弱侧",
            "进攻方应用假传快速转移球"
        ],
        "4 Corners Passing": [
            "双脚锁定或重叠避免被突破",
            "除非进攻方先跳，否则不要跳",
            "身体贴身后用手跟随球",
            "拦截者阅读传球人的肩膀",
            "传球者用假动作和转身创造传球窗口"
        ],
        "Marquette 3v3 Full Court": [
            "迫使持球人用弱手向外侧运球",
            "隔两次传球的防守者必须同时看到球和人",
            "持球压力是必须的",
            "防守随球移动",
            "隔两次传球的防守者必须领先于球"
        ],
        "Charge To Scramble": [
            "在禁区外造犯规",
            "保持低姿势",
            "持续沟通",
            "消除下一个威胁",
            "进攻方要保持球的移动，不让防守恢复"
        ]
    ]
    
    // MARK: - Variations
    static let variations: [String: [String]] = [
        "2v1 Shooting": [
            "允许接到教练传球的进攻球员突破",
            "允许投篮前横向运一次球",
            "增加竞争性——防守者造成失误可留在场上"
        ],
        "Creighton Rebounding": [
            "第2级：防守者在教练传球前在禁区内转圈",
            "第3级：防守者呈三角形站位（区域），不能卡位正前方的球员"
        ],
        "Around The Cones Transition": [
            "进阶1：2打1",
            "进阶2：2打1加追防者",
            "进阶3：教练在锥桶后传球给进攻球员"
        ],
        "Butler Disadvantage Drill": [
            "允许进攻方在4打3优势时投篮"
        ],
        "4 Corners Passing": [
            "不要求进攻方等待夹击——防守必须快速反应",
            "调整正方形大小来改变难度",
            "对伸手犯规进行惩罚"
        ],
        "Charge To Scramble": [
            "使用两端来增加练习次数"
        ]
    ]
}
