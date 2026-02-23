import Foundation

enum DrillCategory: String, Codable, CaseIterable {
    case shooting, offense, defense, skills, conditioning, warmup, cooldown
    
    var displayName: String {
        switch self {
        case .shooting: return "Shooting"
        case .offense: return "Offense"
        case .defense: return "Defense"
        case .skills: return "Skills"
        case .conditioning: return "Conditioning"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        }
    }
    
    var icon: String {
        switch self {
        case .shooting: return "target"
        case .offense: return "arrow.right.circle"
        case .defense: return "shield"
        case .skills: return "star"
        case .conditioning: return "figure.run"
        case .warmup: return "flame"
        case .cooldown: return "snowflake"
        }
    }
    
    var color: String {
        switch self {
        case .shooting: return "orange"
        case .offense: return "blue"
        case .defense: return "red"
        case .skills: return "purple"
        case .conditioning: return "green"
        case .warmup: return "yellow"
        case .cooldown: return "cyan"
        }
    }
}

enum DifficultyLevel: String, Codable, CaseIterable {
    case beginner, intermediate, advanced
    var displayName: String { rawValue.capitalized }
    var color: String {
        switch self {
        case .beginner: return "green"
        case .intermediate: return "orange"
        case .advanced: return "red"
        }
    }
    var stars: Int {
        switch self {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        }
    }
    var level: Int {
        switch self {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        }
    }
}

struct DrillItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: DrillCategory
    var difficulty: DifficultyLevel
    var durationMinutes: Int
    var description: String
    var instructions: [String]
    var keyPoints: [String]
    var equipmentNeeded: [String]
    var minPlayers: Int
    var maxPlayers: Int?
    var variations: [String]
    var videoUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, category: DrillCategory,
         difficulty: DifficultyLevel = .beginner, durationMinutes: Int = 10,
         description: String = "", instructions: [String] = [], keyPoints: [String] = [],
         equipmentNeeded: [String] = [], minPlayers: Int = 1, maxPlayers: Int? = nil,
         variations: [String] = [], videoUrl: String? = nil, tags: [String] = [],
         isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.category = category
        self.difficulty = difficulty
        self.durationMinutes = durationMinutes
        self.description = description
        self.instructions = instructions
        self.keyPoints = keyPoints
        self.equipmentNeeded = equipmentNeeded
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.variations = variations
        self.videoUrl = videoUrl
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var playerRange: String {
        if let max = maxPlayers { return "\(minPlayers)-\(max) players" }
        return "\(minPlayers)+ players"
    }
    
    static let samples: [DrillItem] = [
        DrillItem(name: "Form Shooting", category: .shooting, difficulty: .beginner,
                 durationMinutes: 10, description: "Close-range shooting focusing on proper form",
                 instructions: ["Start 3 feet from basket", "Focus on BEEF", "Make 10 before moving back"],
                 keyPoints: ["Elbow under ball", "Snap wrist", "Hold follow-through"],
                 equipmentNeeded: ["Basketball", "Hoop"], tags: ["fundamentals", "form"]),
        DrillItem(name: "Spot Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 15, description: "Shooting from 5 spots around the arc",
                 instructions: ["5 spots: corners, wings, top", "3 shots each spot", "Track makes"],
                 keyPoints: ["Consistent footwork", "Quick release"], maxPlayers: 4),
        DrillItem(name: "Stationary Dribbling", category: .skills, difficulty: .beginner,
                 durationMinutes: 8, description: "Basic dribbling moves while stationary",
                 instructions: ["Right hand 30s", "Left hand 30s", "Crossover 30s", "Between legs 30s"],
                 keyPoints: ["Eyes up", "Low dribble", "Fingertip control"]),
        DrillItem(name: "Defensive Slides", category: .defense, difficulty: .beginner,
                 durationMinutes: 8, description: "Lateral movement and defensive positioning",
                 instructions: ["Start in stance", "Slide baseline to baseline", "Stay low"],
                 keyPoints: ["Low stance", "Active hands", "Quick feet"]),
        DrillItem(name: "3-Man Weave", category: .offense, difficulty: .beginner,
                 durationMinutes: 10, description: "Classic passing and movement drill",
                 instructions: ["3 players across baseline", "Pass and go behind", "Finish with layup"],
                 keyPoints: ["Crisp passes", "Communication"], minPlayers: 3, maxPlayers: 12),
        DrillItem(name: "Pick and Roll", category: .offense, difficulty: .intermediate,
                 durationMinutes: 15, description: "Two-man pick and roll execution",
                 instructions: ["Ball handler initiates", "Screener sets screen", "Read defense"],
                 keyPoints: ["Screen angle", "Timing", "Read and react"], minPlayers: 2, maxPlayers: 4),
        DrillItem(name: "Suicides", category: .conditioning, difficulty: .intermediate,
                 durationMinutes: 10, description: "Classic basketball conditioning drill",
                 instructions: ["Sprint to free throw and back", "Sprint to half and back", "Full court"],
                 keyPoints: ["Touch every line", "Full speed"]),
        DrillItem(name: "Dynamic Stretching", category: .warmup, durationMinutes: 8,
                 description: "Full body dynamic warm-up routine",
                 instructions: ["High knees 30s", "Butt kicks 30s", "Leg swings", "Arm circles"],
                 keyPoints: ["Gradual intensity", "Full range of motion"]),
        
        // MARK: - Breakthrough Basketball Drills
        DrillItem(name: "2v1 Shooting", category: .offense, difficulty: .intermediate,
                 durationMinutes: 10, description: "A competitive drill to work on shot or pass decision-making in a 2-on-1 advantage situation. Players get game shots while the defender works on closing out and contesting.",
                 instructions: ["Place 2 offensive players anywhere on the court, one pass away from each other", "1 defensive player starts close to the basket", "Coach passes to either offensive player", "Defender closes out on the ball", "Offense can shoot or pass (1 pass limit)", "Defense contests the shot"],
                 keyPoints: ["Emphasize passes being on time and on target", "Offensive players should look at rim before making the pass", "Think shot first - if defender is more than an arm's length away, shoot", "Defender should stunt at receiver and get hand in passing lane", "Defender's goal is to make the weaker shooter take the contested shot"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 6,
                 variations: ["Allow offensive player who receives coach's pass to drive", "Allow one side dribble before shooting", "Make it competitive - defense stays if they force a miss"],
                 tags: ["decision-making", "closeouts", "shooting"]),
        
        DrillItem(name: "Creighton Rebounding", category: .defense, difficulty: .beginner,
                 durationMinutes: 8, description: "A small-sided rebounding game that creates player toughness and teaches proper box-out technique in various situations.",
                 instructions: ["Position 3 offensive players around the perimeter", "3 defenders start in the paint", "Coach passes to an offensive player", "All defenders close out", "Offensive player shoots immediately", "Defenders must box out and grab the rebound"],
                 keyPoints: ["Box out technique: hit, locate, and get the rebound", "If offensive player gets past you, sumo out (backside on their thigh)", "First contact must happen outside the key", "Communicate in advanced versions", "Team that scores stays on court"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 10,
                 variations: ["Level 2: Defenders circle the wagon in paint before coach passes", "Level 3: Start defenders in triangle (zone), cannot box out player directly in front"],
                 tags: ["rebounding", "box-out", "toughness"]),
        
        DrillItem(name: "Around The Cones Transition", category: .offense, difficulty: .intermediate,
                 durationMinutes: 12, description: "Creates game-like transition situations to work on converting scoring opportunities at various numerical advantages.",
                 instructions: ["Place 3 cones even with top of key (1 at top, 2 at wings)", "Start with 3 lines on baseline", "Player in outside line starts with ball", "All 3 players sprint around cone in front of them", "Play is live after circling cones"],
                 keyPoints: ["Dribbler must use inside hand to protect ball", "Offense gets 1 shot and 1 pass (simulate quick transition)", "Defender should get to front of rim to prevent layup", "Defender should stunt at dribbler to create indecision", "Dribbler attacks until defender gets between them and rim"],
                 equipmentNeeded: ["Basketball", "3 Cones"], minPlayers: 3, maxPlayers: 12,
                 variations: ["Progression 1: 2v1", "Progression 2: 2v1 + Trail defender", "Progression 3: Coach passes to offensive player after cone"],
                 tags: ["transition", "fast-break", "decision-making"]),
        
        DrillItem(name: "Butler Disadvantage Drill", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Shell defense drill with 4v3 advantage that transitions to live 4v4 when the 4th defender recovers.",
                 instructions: ["4 offensive players positioned on wings and corners", "3 defenders start in triangle around lane", "4th defender at half court", "Coach passes to any offensive player", "3 defenders practice shell rotations", "4th defender sprints to opposite baseline and back", "Offense cannot shoot until 4th defender recovers, then live"],
                 keyPoints: ["Ball side covered, 1 player splits 2 on weak side", "Players should not cover 2 passes in a row", "Communication must be loud, early, and continuous", "4th defender should fill weak side when recovering", "Offense should use pass fakes to move ball quickly"],
                 equipmentNeeded: ["Basketball"], minPlayers: 8, maxPlayers: 12,
                 variations: ["Allow offense to shoot during 4v3 advantage"],
                 tags: ["shell-defense", "help-defense", "communication"]),
        
        DrillItem(name: "4 Corners Passing", category: .defense, difficulty: .intermediate,
                 durationMinutes: 5, description: "Trapping and passing drill where offense works on passing out of traps while defense practices proper trapping technique.",
                 instructions: ["Position 4 offensive players in a square", "4 defensive players line up between offensive players", "Pass ball to start - closest 2 defenders trap", "Offensive player holds ball to allow trap", "Other 2 defenders space between 3 offensive players", "Continue for 30 seconds, tracking deflections and steals"],
                 keyPoints: ["Lock or overlap feet to avoid being split", "Don't jump unless offense jumps first", "Get body to body, then mirror ball with hands", "Interceptors read passer's shoulders", "Passers use fakes and pivot to create passing windows"],
                 equipmentNeeded: ["Basketball"], minPlayers: 8, maxPlayers: 12,
                 variations: ["Don't require offense to wait for trap - defense must react", "Make square larger/smaller to adjust difficulty", "Penalize reaching fouls"],
                 tags: ["trapping", "passing", "pressure-defense"]),
        
        DrillItem(name: "Marquette 3v3 Full Court", category: .defense, difficulty: .advanced,
                 durationMinutes: 12, description: "Full court 3v3 emphasizing no middle principles, proper angles, and ball-you-man positioning.",
                 instructions: ["3 offensive players line up across baseline", "3 defenders match up", "Middle offensive player starts with ball", "Defender forces ball to outer thirds with weak hand", "Ball handler has 2 dribbles to punch gap", "Help defender recovers after helping", "Live 3v3 once ball crosses half court"],
                 keyPoints: ["Force ball handler to outer thirds with weaker hand", "Two passes away defender must see ball and man", "Ball pressure is a must", "Defense moves as ball moves", "Defender two passes away must be ahead of ball"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 12,
                 tags: ["full-court-defense", "pressure", "positioning"]),
        
        DrillItem(name: "Charge To Scramble", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Teaches players how to take charges properly while forcing defensive rotation and scramble situations.",
                 instructions: ["Position 3 offensive players on wings and top of key", "Defenders match up with no middle stance", "Start playing 3v3", "Offense swings ball around perimeter", "Player drives baseline, opposite defender draws charge", "Defender falls down selling charge", "Offensive player kicks out, live play begins"],
                 keyPoints: ["Take charge outside the lane", "Stay low and in stance", "Communicate constantly", "Iron out the next threat", "Offense should keep ball moving, don't let defense recover"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 12,
                 variations: ["Use both ends to double reps"],
                 tags: ["charges", "rotation", "scramble"]),
        
        DrillItem(name: "Disadvantage Drill", category: .offense, difficulty: .advanced,
                 durationMinutes: 15, description: "Comprehensive transition drill incorporating 1v0 through 5v5 situations to work on all transition scenarios.",
                 instructions: ["Split team in 2 groups", "1 player starts with ball, shoots FT line jumper", "Possession ends, go back 2v1 opposite direction", "Continue adding players each possession (3v2, 4v3, 5v4, 5v5)", "Only inbound at 5v5"],
                 keyPoints: ["Defensive goal: force jump shot", "PG takes one dribble toward pass for better angle", "Use bounce passes (less likely to be stolen)", "Passes allowed = number of defenders", "Shot attempts allowed = number of offensive players", "Defense forms appropriate disadvantage formations"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 20,
                 tags: ["transition", "numbers-advantage", "fast-break"]),
        
        DrillItem(name: "2v2 Zoom", category: .offense, difficulty: .intermediate,
                 durationMinutes: 12, description: "Teaches zoom action (dribble handoff) against different defensive coverages including no switch, switching, and blitzing.",
                 instructions: ["Position offensive player in slot and on wing", "Defenders match up", "Coach starts with ball on opposite wing", "Coach enters to slot player", "Execute zoom action based on defensive coverage"],
                 keyPoints: ["Both players scan defense as they approach handoff", "Deeper trigger gets, farther defender must go to switch", "Good setup important - wing can go backdoor if overplayed", "Pitch should be soft toss to torso", "Don't pick up ball early after switch"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 10,
                 variations: ["Variation 1: No Switch (fight over/under)", "Variation 2: Switching Defense", "Variation 3: Blitzing Defense (trap)"],
                 tags: ["zoom", "dribble-handoff", "reads"]),
        
        DrillItem(name: "3v3 One Side Of The Court", category: .offense, difficulty: .beginner,
                 durationMinutes: 10, description: "Teaching spacing drill using only one side of court to create game-like condensed space for young players.",
                 instructions: ["Position 3 offensive players on 1 side of court", "3 defenders guard them", "Player 1 passes to player 2", "Defense cannot steal initial pass", "Player 1 cuts to basket", "If not open, player 2 dribbles to top", "Play continues from there"],
                 keyPoints: ["Players quickly learn they can't stand still", "Adjust space size to help/challenge defense", "Can add other actions besides cutting", "Consider dribble limit (2 dribbles per touch)"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 12,
                 variations: ["Add screening actions", "Implement dribble limits"],
                 tags: ["spacing", "youth", "condensed-space"]),
        
        DrillItem(name: "Full Court 1v1 With Closeout", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Works on full court ball pressure followed by a closeout and 1v1 defense.",
                 instructions: ["Offense and defense start on baseline with ball", "Offensive player tries to beat defender down floor", "Defender tries to turn ball as many times as possible", "Once ball crosses half court, offense passes to coach on sideline", "Offense sprints and touches half court", "Defense sprints and touches baseline", "Coach passes to offense, defender closes out", "Play 1v1"],
                 keyPoints: ["Close out based on scouting - shooters need closer closeout", "Close out with proper stance angle for your zone", "Encourage offense to attack on catch", "Holding ball should be a turnover"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 10,
                 tags: ["closeouts", "full-court", "1v1"]),
        
        DrillItem(name: "Navy Transition", category: .offense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Simulates game randomness by rolling ball out and playing live from scramble situations to build IQ and competitiveness.",
                 instructions: ["Each team has 5 players on floor", "Coach has ball to start", "Coach rolls out ball anywhere on court", "Whichever team gets ball is on offense to far side", "Play live from there"],
                 keyPoints: ["Defense must sprint, point, and talk immediately", "Player gathering ball should get head up and scan", "Gather ball in power position", "Other 4 offensive players get to spacing spots in 5 seconds", "Can allow offense to go either direction for added challenge"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 10,
                 variations: ["Allow offense to choose direction after gathering ball"],
                 tags: ["transition", "decision-making", "IQ"]),
        
        DrillItem(name: "2 Minute Closeouts", category: .defense, difficulty: .beginner,
                 durationMinutes: 2, description: "Daily drill to build proper closeout habits and jumping to the ball technique.",
                 instructions: ["Coach at top with ball", "2 players (or coaches) on each wing", "Line of defenders under rim, first 2 on midline", "Coach passes to wing", "Defender closes out", "Continue passing, defenders rotate and closeout", "Run continuously for 2 minutes"],
                 keyPoints: ["Emphasize proper footwork on closeouts", "Jump to ball on every pass", "Offense should fake/jab at defender on catch", "Take away shot with high hand, then bring hands down for drive", "Give space when ball brought low in case of drive"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
                 variations: ["Progress to 4v4 to include more players and spots"],
                 tags: ["closeouts", "shell", "warmup"]),
        
        DrillItem(name: "Full Court 1v1 With Turns", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Teaches full court ball pressure with emphasis on turning the ball handler and containing dribble.",
                 instructions: ["Offensive and defensive players start on baseline", "Offense has ball", "Offensive player tries to beat defender down floor", "Defender tries to turn ball as many times as possible", "Once ball crosses half court, play live 1v1"],
                 keyPoints: ["Stress proper defensive footwork", "Use combination of sliding and sprinting", "Limit space offensive player can use", "Play through the rebound", "Can switch O/D every time or defender stays until stop"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 10,
                 variations: ["Give offense half floor or adjust width", "Defender stays on until getting a stop"],
                 tags: ["full-court-defense", "ball-pressure", "1v1"]),
        
        DrillItem(name: "Ball Screen Defense Drill", category: .defense, difficulty: .advanced,
                 durationMinutes: 12, description: "Teaches three different ball screen coverages: drop, flat hedge, and trap with proper rotations.",
                 instructions: ["5 offensive players (blocks and wings)", "3 defensive players (blocks and top)", "Start with pass to wing", "Defender sprints to cover wing", "Execute ball screen coverage (drop, hedge, or trap)", "After each rep, pass to opposite wing and repeat"],
                 keyPoints: ["On-ball defender must force ball handler to use screen", "Get skinny to present smaller target for screener", "Big must communicate coverage with color/term", "Feet touching on trap so can't get split", "High hands on hedge to deter pass to roller"],
                 equipmentNeeded: ["Basketball"], minPlayers: 8, maxPlayers: 12,
                 variations: ["Rep 1: Drop coverage", "Rep 2: Flat hedge", "Rep 3: Trap", "Can go live at any point"],
                 tags: ["ball-screens", "pick-and-roll", "coverage"]),
        
        DrillItem(name: "Offensive Cutthroat", category: .offense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Competitive small-sided game with specific offensive rules that teams must follow or rotate out.",
                 instructions: ["Can be played 3v3, 4v4, or 5v5", "Three teams rotate through", "Coaches create rules that must be followed", "If rule isn't followed, team rotates out", "If offense scores, they stay", "If defense stops them, they go to offense"],
                 keyPoints: ["Example rules: no wasted dribbles, hard cuts, play off 2 feet in lane", "Don't let ball die in hands", "Thank passer on made basket", "Tailor rules to your system", "Include cultural 'musts' like pointing to passer"],
                 equipmentNeeded: ["Basketball"], minPlayers: 9, maxPlayers: 15,
                 variations: ["Use defensive rules instead of offensive"],
                 tags: ["competitive", "rules", "culture"]),
        
        DrillItem(name: "1v2 Zone Press Drill", category: .offense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Teaches ball handlers to value the ball under pressure while defenders work on trapping angles.",
                 instructions: ["Player 2 with ball at free throw line area", "Player 1 on sideline level with player 2", "X2 guards player 2, X1 waits at opposite volleyball line", "Cones down center limit area", "Player 2 passes to player 1, then out of play", "Player 1 attacks with speed", "Defenders sprint to trap", "Play until offense reaches volleyball line or turnover"],
                 keyPoints: ["Good trapping angles and lock feet when trapping", "Offense attacks with speed", "Attack and split/beat trap with one hard move", "Adjust cone placement for difficulty", "Can have offense try to score instead of just reaching line"],
                 equipmentNeeded: ["Basketball", "Cones"], minPlayers: 3, maxPlayers: 12,
                 variations: ["Move dribbler ahead or behind passer to adjust difficulty", "Have offense score instead of just reaching line"],
                 tags: ["press-break", "trapping", "ball-handling"]),
        
        DrillItem(name: "Monkey In The Middle", category: .skills, difficulty: .beginner,
                 durationMinutes: 5, description: "Youth passing drill where two players pass while defender in middle tries to deflect.",
                 instructions: ["Two players on offense", "One player in middle is monkey (defense)", "Offensive players pass back and forth", "Use fakes to get ball past defender", "No lob passes allowed", "Wait for defender to recover before next pass", "When defender tips pass, passer becomes monkey"],
                 keyPoints: ["Use pass fakes", "Make crisp passes", "Defender should anticipate and react", "Focus on proper passing technique"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 3,
                 tags: ["youth", "passing", "footwork"]),
        
        DrillItem(name: "Bull In The Ring", category: .skills, difficulty: .beginner,
                 durationMinutes: 5, description: "Youth passing drill with 4-5 players forming circle around defender trying to deflect passes.",
                 instructions: ["4-5 players form circle around defender (bull)", "Offensive players pass around circle", "Cannot pass to person next to them", "When ball is tipped, passer becomes bull"],
                 keyPoints: ["Use pass fakes", "Quick ball movement", "Defender reads and anticipates", "Crisp chest passes"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 6,
                 tags: ["youth", "passing", "anticipation"]),
        
        DrillItem(name: "5v3 + 2 Fast Break", category: .offense, difficulty: .beginner,
                 durationMinutes: 10, description: "Youth fast break drill starting with Annie Over, creating 5v3 advantage that becomes 5v5.",
                 instructions: ["Start with Annie Over (coach says Go)", "Offense rebounds, pitches out, runs break", "Two defenders at midcourt wait for ball to cross half", "Those defenders touch hands at middle, sprint to join defense", "Can reset after possession or run continuously"],
                 keyPoints: ["Quick outlet after rebound", "Push ball in transition", "Defenders must communicate and sprint back", "Fill lanes properly"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 10,
                 variations: ["Reset after each possession", "Run continuously back and forth"],
                 tags: ["youth", "fast-break", "transition"]),
        
        DrillItem(name: "5v0 Pass & Cut", category: .offense, difficulty: .beginner,
                 durationMinutes: 8, description: "Youth shell offense drill teaching passing, cutting, and spacing without defense.",
                 instructions: ["Players start in 5 out spots on 3-point line", "Run offense without taking shots", "Pass left or right, then cut to basket", "Other players replace to open areas", "If cutter doesn't get ball, fill open corner", "Continue pattern"],
                 keyPoints: ["Cut hard all the way to basket", "Look for ball as you cut", "Passer watches cutter", "No banana cuts - crisp cuts only", "Use hand signals when filling"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 10,
                 tags: ["youth", "cutting", "spacing"]),
        
        DrillItem(name: "5v0 Pass & Pick Away", category: .offense, difficulty: .beginner,
                 durationMinutes: 8, description: "Youth shell offense drill teaching screening away and curling without defense.",
                 instructions: ["Players pass and screen away every time", "Player receiving screen sets up then curls to basket", "Screener opens to ball", "Other player fills open spot", "Cutter clears to corner", "Continue screening pattern"],
                 keyPoints: ["Call out screen verbally and with fist", "Set up the screen properly", "Cutter comes off shoulder to hip", "Curl all way to backboard then find spot", "Screener pops as cutter brushes shoulder"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 10,
                 tags: ["youth", "screening", "curls"]),
        
        DrillItem(name: "Figure 8 Shooting", category: .shooting, difficulty: .beginner,
                 durationMinutes: 8, description: "Shooting drill combining footwork and shooting with front pivots using chairs.",
                 instructions: ["Put 2 chairs on wing with ball in each", "Player starts between chairs", "Run around right chair, grab ball, front pivot, shoot", "Run between chairs and around left chair", "Grab ball, front pivot, shoot", "Continue pattern for 10 shots", "Repeat on other side"],
                 keyPoints: ["Stay low and make hard front pivot into shot", "Best done with partner rebounding and replacing balls", "Adjust shooting distance to experience and ability"],
                 equipmentNeeded: ["2 Basketballs", "2 Chairs"], minPlayers: 1, maxPlayers: 4,
                 tags: ["shooting", "footwork", "pivoting"]),
        
        DrillItem(name: "Chair Pivots", category: .skills, difficulty: .intermediate,
                 durationMinutes: 10, description: "Develops comfort with all pivots in attack and counter system. Works on various pivot combinations and finishes.",
                 instructions: ["Place chair on each side above block with ball in each", "1 shooter, 1 rebounder, 2 ball replacers", "Shooter sprints to chair, jump stops, grabs ball", "Get in triple threat, make specific pivot and score", "Sprint to opposite chair and repeat", "Continue for set shots (10) or time (1:00)"],
                 keyPoints: ["Practice all pivot variations: front, inside, drop step", "Work both baseline foot and top foot", "Top foot = closest to key, baseline foot = closest to baseline", "Can make it 1v1 after practicing without defense"],
                 equipmentNeeded: ["2 Basketballs", "2 Chairs"], minPlayers: 2, maxPlayers: 4,
                 variations: ["12 different pivot combinations listed in drill", "Add defense for 1v1 version"],
                 tags: ["footwork", "pivoting", "finishing"]),
        
        DrillItem(name: "Ball Screen Reads", category: .skills, difficulty: .intermediate,
                 durationMinutes: 12, description: "Works on different ball screen reads against common coverages using chairs to simulate defenders and screens.",
                 instructions: ["Line players at half court on sideline with ball", "2 chairs (1 for defender, 1 for screen)", "Player dribbles below screen to set up", "Execute specific read based on coverage", "Rotate through: over the top, reject, drag, split"],
                 keyPoints: ["Set up defender properly below screen", "Use change of pace to beat hedger", "Push ball out to create space after split", "Perform each scenario 4-6x on each side", "Add guided defense to force reads"],
                 equipmentNeeded: ["Basketball", "2 Chairs"], minPlayers: 3, maxPlayers: 12,
                 variations: ["Over the top vs drop", "Reject the screen", "Drag vs hedge", "Split vs hedge"],
                 tags: ["ball-screens", "reads", "decision-making"]),
        
        DrillItem(name: "Chair 1v1", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Competitive shooting game combining attack footwork with 1v1 play from chairs.",
                 instructions: ["2 players start on baseline", "3 chairs on wings and top with balls", "On go, both run to wing chair, pivot, shoot (2 points if made)", "Race to top chair - first to get ball is on offense", "Play 1v1 with 2 dribbles (1 point if scored)", "First to 5 wins"],
                 keyPoints: ["Switch starting sides each reset", "Can prescribe pivot or let players choose", "Scan defense location when getting ball for 1v1", "Quickly utilize proper footwork and attack"],
                 equipmentNeeded: ["3 Basketballs", "3 Chairs"], minPlayers: 2, maxPlayers: 6,
                 tags: ["shooting", "competitive", "1v1"]),
        
        // MARK: - Breakthrough Basketball Drills (Batch 2)
        DrillItem(name: "Partner Shooting", category: .shooting, difficulty: .beginner,
                 durationMinutes: 3, description: "Warmup shooting drill with partner, progressing from free throw line to 3-point line with movement.",
                 instructions: ["1 shooter, 1 rebounder, 1 ball", "Minute 1: Catch and shoot from free throw line", "Minute 2: Move back to top of key, shoot 3s", "Minute 3: Shoot 3s while moving between shots"],
                 keyPoints: ["Work on shot prep - show hands to passer", "Be down and ready to shoot", "Vary footwork - hop, step into pass", "Mix running and sliding in minute 3", "Move with slight arc for good shooting angle"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 20,
                 tags: ["shooting", "warmup", "form"]),
        
        DrillItem(name: "20 Shooting", category: .shooting, difficulty: .advanced,
                 durationMinutes: 2, description: "Challenging shooting drill requiring 3 makes in a row from 5 spots, then 5 in a row coming back.",
                 instructions: ["Use 5 spots: corners, wings, top of key", "Make 3 in a row from each spot", "When reaching opposite corner, make 5 in a row coming back", "2 minutes to complete", "Score: 3 points per spot in round 1 plus how far you get in round 2"],
                 keyPoints: ["Hold follow through despite time pressure", "Be quick but don't hurry", "Stay positive - mental drill too", "Work on next shot mentality"],
                 equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 4,
                 tags: ["shooting", "mental-toughness", "pressure"]),
        
        DrillItem(name: "14 in :90", category: .shooting, difficulty: .advanced,
                 durationMinutes: 2, description: "Timed shooting drill using 7 spots requiring 2 makes in a row to advance.",
                 instructions: ["7 spots: corners, low wings, high wings, top", "Make 2 in a row to move to next spot", "Each spot worth 2 points", "After completing all 7, each additional 3 = 1 point", "90 seconds to complete"],
                 keyPoints: ["Hold follow through", "Be quick but don't hurry", "Stay positive despite misses", "Sprint spot to spot to maximize time", "Be shot ready for maximum attempts"],
                 equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 4,
                 tags: ["shooting", "conditioning", "pressure"]),
        
        DrillItem(name: "Big Shot", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Shooting drill with pressure from misses instead of time. Shoot until missing 2 in a row.",
                 instructions: ["5 spots: corners, wings, top", "Shoot until you miss 2 in a row", "Once 2 misses in a row, move to next spot", "Every make worth 1 point", "Score is total makes over all 5 spots"],
                 keyPoints: ["Focus only on shot at hand", "Don't let last shot affect next shot", "Rough start can be overcome by great spot", "Maintain good form when tired", "Stay disciplined as fatigue sets in"],
                 equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 4,
                 tags: ["shooting", "mental-toughness", "focus"]),
        
        DrillItem(name: "Nuggets Drill", category: .shooting, difficulty: .advanced,
                 durationMinutes: 12, description: "Combines shooting on the move with conditioning element. Sprint penalty for 2 misses in a row.",
                 instructions: ["5 spots: corners, wings, top", "Make 3 in a row at each spot", "Corners: slide to wing, drift back for catch and shoot 3", "Wings: sprint to volleyball line and back for transition 3", "Top: sprint to half court and back for transition 3", "2 misses in a row = sprint to opposite baseline and back"],
                 keyPoints: ["Aim for BRAD (back rim and down) when tired", "Focus on footwork when catching on move", "SPRINT transition 3s to simulate game", "Score is time to complete all 5 spots"],
                 equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 4,
                 tags: ["shooting", "conditioning", "movement"]),
        
        DrillItem(name: "Arc Finishing", category: .skills, difficulty: .intermediate,
                 durationMinutes: 10, description: "Layup drill using cones to simulate coming from different angles to the basket.",
                 instructions: ["Set up 5 cones around 3-point line", "Dribble with right hand around first cone", "Come back to basket for right-handed layup", "Progress through each cone", "After all 5 with right hand, repeat with left hand", "Complete 10 layups total (5 each hand)"],
                 keyPoints: ["Extend ball as you get around cone to accelerate", "Chin up / eyes up when finishing", "Drive knee to nose for maximum height", "Perform at full speed to simulate game", "Use different finishing moves: Rondo, Euro, Runner"],
                 equipmentNeeded: ["Basketball", "5 Cones"], minPlayers: 1, maxPlayers: 8,
                 variations: ["Add different finishing moves"],
                 tags: ["finishing", "layups", "ball-handling"]),
        
        DrillItem(name: "1v1 Cone Touch", category: .skills, difficulty: .intermediate,
                 durationMinutes: 10, description: "Competitive 1v1 drill where players sprint to touch cones before playing live.",
                 instructions: ["Set up pair of cones near perimeter", "When offensive player moves forward, both sprint to cones", "Passer throws ball to offense near basket", "Live 1v1 after catch", "Start offensive cone closer to hoop for advantage"],
                 keyPoints: ["Adjust cone distance for defender arrival timing", "Defender shouldn't steal the pass", "Can work with partner", "Focus on finishing under pressure"],
                 equipmentNeeded: ["Basketball", "2 Cones"], minPlayers: 2, maxPlayers: 8,
                 variations: ["Can set ball on chair if working alone"],
                 tags: ["1v1", "finishing", "competitive"]),
        
        DrillItem(name: "Euro Step Drill", category: .skills, difficulty: .intermediate,
                 durationMinutes: 10, description: "Progressive drill teaching Euro Step finishing move with proper footwork.",
                 instructions: ["Progression 1: Two steps no dribble (learning footwork)", "Progression 2: Add dribble, start inside 3-point line", "Progression 3: Euro step from 3-point line", "Practice from all angles and distances"],
                 keyPoints: ["Focus on long, explosive steps", "Practice from different angles and distances", "Can add change of direction if defender recovers", "Use defender's momentum against them"],
                 equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 8,
                 tags: ["finishing", "footwork", "euro-step"]),
        
        DrillItem(name: "Baseline Drive Team Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Team shooting drill working baseline drive, drift, and one more pass.",
                 instructions: ["Three lines of players", "Middle line behind half court with ball", "Player 1 pitches to Player 2", "Player 3 drifts to coffin corner", "Player 2 drives baseline, passes to Player 3", "Player 1 runs to wing for one more pass and shoots", "Player 4 passes to Player 3 for second shot"],
                 keyPoints: ["Player 3 can shot fake before passing", "Player 2 should puncture lane before passing", "Getting in lane allows opposite drift for three", "Rotate after every possession", "Goal is to force long closeouts"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 15,
                 variations: ["Shoot for singles, doubles, or triples"],
                 tags: ["team-shooting", "drive-and-kick", "spacing"]),
        
        DrillItem(name: "Drag Screen Team Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Team shooting drill simulating drag screen action in transition with four out one in spacing.",
                 instructions: ["Point guard, strong side wing, big at four spot", "Passing line on weak side wing", "Player 2 sprints to corner", "Player 5 sets drag screen for Player 1", "Player 1 dribbles off screen toward basket", "Player 5 rim runs, receives pass for layup", "Player 2 drifts up for lift shot from Player 3"],
                 keyPoints: ["Point guard decides based on defense", "If switch, Player 5 available on rim run", "If wing defender helps, use hook pass", "Place all players in all positions for development", "All shots done on the move, game-like"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 15,
                 tags: ["team-shooting", "drag-screen", "transition"]),
        
        DrillItem(name: "Pistol Action Team Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Team shooting drill using pistol action (dribble handoff into screen) common at high levels.",
                 instructions: ["Player 2 sprints to corner", "Player 1 executes dribble handoff to Player 2", "Player 1 drifts to corner", "Player 4 sprints to screen for Player 2", "Player 4 rolls to basket, receives pass", "Player 1 drifts to top for shot from Player 3"],
                 keyPoints: ["Point guard must create space if DHO gets blown up", "Point guard ready to lift after DHO", "Practicing game situations increases 3-point percentage", "Hard to defend at college and NBA levels"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 15,
                 tags: ["team-shooting", "pistol-action", "dribble-handoff"]),
        
        DrillItem(name: "Post Entry Team Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Team shooting drill executing Laker cut from post entry in transition.",
                 instructions: ["Player 1 passes ahead to Player 2", "Player 3 runs and stops above block", "Player 2 enters to post (Player 3)", "Player 2 executes Laker cut, receives pass", "Player 1 drifts to corner for shot from Player 4"],
                 keyPoints: ["Alternative option once defense stops one action", "Offense can backdoor or go over screen", "Players getting game shots at game speed", "Building IQ through spacing and concepts", "Actions become reads during game"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 15,
                 tags: ["team-shooting", "post-entry", "laker-cut"]),
        
        DrillItem(name: "DHO Reject Team Shooting", category: .shooting, difficulty: .intermediate,
                 durationMinutes: 10, description: "Team shooting drill teaching how to reject dribble handoff with backdoor cut.",
                 instructions: ["If defender overplays DHO, signal backdoor", "Player 2 backdoor cuts before DHO", "Receives pass from Player 1 for layup", "Player 4 screens for Player 1", "Player 1 flares for shot from Player 3"],
                 keyPoints: ["Don't make dribbler guess - develop signal", "Open hand = accept DHO, closed fist = reject", "Point guard flares ready to catch and shoot", "Use consistent terminology (flare vs fade)", "Timing critical - don't get too far from passer"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 15,
                 tags: ["team-shooting", "dribble-handoff", "backdoor"]),
        
        DrillItem(name: "1 on 1 Closeout", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Fast-paced drill practicing closeouts, contesting shots, and preventing penetration in 1v1.",
                 instructions: ["Defenders X1 and X2 start under basket with balls", "Two offensive players on wings", "X2 passes to wing player 2, follows with hard closeout", "Defender keeps ball out of paint, forces contested jumper", "Box out and rebound"],
                 keyPoints: ["Sprint to eliminate offensive advantage", "Hands up to contest shot and passes", "Position appropriately based on philosophy", "Practice good offensive habits too", "Progression: touch before going live, then immediate live"],
                 equipmentNeeded: ["2 Basketballs"], minPlayers: 4, maxPlayers: 12,
                 variations: ["Loser stays on defense", "Add passer for unpredictability", "Vary passing positions", "Add time/dribble limits"],
                 tags: ["closeouts", "1v1-defense", "contesting"]),
        
        DrillItem(name: "Man In The Hole", category: .defense, difficulty: .advanced,
                 durationMinutes: 12, description: "Challenging full court 1v1 drill where one defender faces three ball handlers consecutively.",
                 instructions: ["Ball handler 2 starts on baseline with ball", "Defender X1 in front ready to play defense", "Offensive player tries to beat defender down floor", "Defender stops ball from advancing", "At other end, hand off to player 4 going back", "X1 defends again, then defends player 3 third time", "After three possessions, X1 is out of hole"],
                 keyPoints: ["Number one goal: stop ball from advancing", "Use push step (shuffle) and sprint", "If beaten, turn and sprint to cut off", "Offense practices protecting ball and change of pace", "Go back to where beaten if offense gets by"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
                 variations: ["Split court into 3-4 alleys for full team"],
                 tags: ["full-court-defense", "conditioning", "toughness"]),
        
        DrillItem(name: "1v1 to 3v3 Full Court", category: .defense, difficulty: .advanced,
                 durationMinutes: 12, description: "Builds 1v1 full court defense habits transitioning into half court 3v3 team defense.",
                 instructions: ["Ball handler starts on baseline with defender", "Two offensive and defensive players on opposite end", "Ball handler advances ball trying to beat defender", "Once past half court, live 3v3", "After possession, defense turns to offense"],
                 keyPoints: ["Contain ball - no straight line drives", "Wing defenders deny pass", "Be ready to help and recover", "Help across not up from your player", "Force contested jump shots, no layups"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 12,
                 variations: ["Reward turns before half court", "Defense stops - new defenders if no stop", "Winner stays format"],
                 tags: ["full-court-defense", "transition-defense", "3v3"]),
        
        DrillItem(name: "4v4 Shell Drill", category: .defense, difficulty: .intermediate,
                 durationMinutes: 15, description: "Comprehensive shell drill teaching all defensive concepts through progressive stages.",
                 instructions: ["Position 4-5 offense on perimeter with defenders", "Progression 1: Positioning - pass and check positioning", "Progression 2: Interchange positions", "Progression 3: Baseline drive with rotations", "Progression 4: Live play", "Progression 5: Down screens", "Progression 6: Back screens"],
                 keyPoints: ["Jump to ball, don't react to catch", "No layups - seal seams", "Don't hug player setting screen", "Go ball side of down screen", "No lobs on back screens - non-negotiable", "Get skinny when screened"],
                 equipmentNeeded: ["Basketball"], minPlayers: 8, maxPlayers: 15,
                 variations: ["Can add offensive actions: cuts, screens, etc."],
                 tags: ["shell-defense", "help-defense", "screens"]),
        
        DrillItem(name: "4 on 3 Overload", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Defense constantly at disadvantage, forcing hustle, communication, and rotation.",
                 instructions: ["3 defenders, 4 offensive players", "Ball starts on wing", "As ball passed, defenders scramble to cover", "Ball can be skipped, players can penetrate in areas", "Progress to live 4v3"],
                 keyPoints: ["Effective closeouts essential", "Sprint to areas with maximum effort", "Communication required", "Someone always open but good positioning controls it"],
                 equipmentNeeded: ["Basketball"], minPlayers: 7, maxPlayers: 12,
                 variations: ["Can do 5v4", "Add offensive movement and screens"],
                 tags: ["scramble", "rotation", "help-defense"]),
        
        DrillItem(name: "No Paint Drill", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Drill focused on eliminating paint penetration via pass or dribble.",
                 instructions: ["4 offensive and 4 defensive players", "Coach or manager at top with ball", "Coach passes to start drill", "Offense gets point for penetrating paint via dribble or pass", "Change possession on points, turnovers, rebounds", "First team to 3 wins"],
                 keyPoints: ["Keep ball from penetrating lane", "Low number makes it competitive and intense", "Award point for 3-point shot hitting rim (progression)", "Award points for excessive fouling to teach smart defense"],
                 equipmentNeeded: ["Basketball"], minPlayers: 9, maxPlayers: 12,
                 variations: ["Add 3-point shot hitting rim for point", "Penalize excessive fouling"],
                 tags: ["paint-protection", "no-middle", "competitive"]),
        
        DrillItem(name: "5v4 Whistle Change", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Works on scrambling and picking up different players when game situations force switches.",
                 instructions: ["5 offensive and 5 defensive players matched up", "Start playing 5v5 live", "On whistle, offense sets ball down", "Defense (not ball defender) picks up ball", "That team now on offense", "Other team scrambles to guard someone (not their previous matchup)"],
                 keyPoints: ["Communication required - players must talk", "Be aware of ball handler while matching up", "Stop ball when necessary with help", "Keep coaching proper defensive fundamentals"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 10,
                 variations: ["Can play full court"],
                 tags: ["scramble", "communication", "transition"]),
        
        DrillItem(name: "4v4 With Baseline Drivers", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Team defense drill with designated baseline drivers creating help and recover situations.",
                 instructions: ["4 offensive and 4 defensive players", "2 baseline drivers in corners (not actively guarded)", "Start drill, 4v4 live", "Baseline driver can drive or pass immediately", "If drive, defense must stop ball and rotate", "Progress to allow offense to penetrate and interchange"],
                 keyPoints: ["See player and ball at all times", "Help early and quick - sprint to spots", "Teach when NOT to help (player has position)", "Mix up baseline driver actions (drive vs pass)"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 10,
                 tags: ["help-defense", "rotation", "recovery"]),
        
        DrillItem(name: "5v2 Weak Side Help", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Isolates two defenders to work on positioning, flash cutters, and interchanges.",
                 instructions: ["5 offensive players on perimeter", "2 defenders matched up man to man", "Ball passed to wing - defenders jump to ball", "Ball can be skipped across", "Offensive players may flash cut or interchange", "Run for 20 seconds then rotate"],
                 keyPoints: ["Constant communication between defenders", "Sprint to areas - 100% effort required", "Move with pass, not on catch", "See ball and man at all times"],
                 equipmentNeeded: ["Basketball"], minPlayers: 7, maxPlayers: 12,
                 tags: ["help-defense", "weak-side", "positioning"]),
        
        DrillItem(name: "Complete Man To Man Drill", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Defender transitions through different positions: 1 pass away, 2 passes away, post defense, flash cuts, closeouts.",
                 instructions: ["Coach/manager/player at top with ball", "Defender guarding player on wing", "Coach starts with ball - defender in 1 pass away position", "Coach dribbles to wing, offensive player posts up", "Offensive player moves to weak side wing", "Offensive player flash cuts, defender picks up", "If catch, live 1v1"],
                 keyPoints: ["Up the line, on the line positioning", "Always see player and ball", "Step in front of cutter", "Hand in passing lane on backdoor", "Mix up cuts and positions randomly"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 8,
                 variations: ["Randomly vary offensive actions"],
                 tags: ["man-defense", "positioning", "fundamentals"]),
        
        DrillItem(name: "2 on 2 Ball Screens", category: .defense, difficulty: .advanced,
                 durationMinutes: 12, description: "Challenging 2v2 with no help defense, focusing on ball screen coverage and dribble handoffs.",
                 instructions: ["2 offensive and 2 defensive players", "Ball handler at top or wing", "First action is always ball screen", "Defender hedges ball handler east-west", "On-ball defender fights over top", "Switch on all dribble handoffs"],
                 keyPoints: ["Hedger stays tight, don't get split", "Don't allow screener straight line path", "On-ball defender beats screen if possible", "Quickly reposition on handoff switches", "No help makes it harder than games"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
                 variations: ["Can play 3v3 or 4v4", "Allow offensive advantage on ball screen"],
                 tags: ["ball-screens", "hedging", "switching"]),
        
        DrillItem(name: "B.U. Closeouts", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Defender on island against 3 offensive players, working closeouts, angles, and rebounding.",
                 instructions: ["Defender starts under basket with ball", "3 offensive players positioned around perimeter", "Defender passes to one offensive player", "Close out and defend (2 dribble limit for offense)", "Hit and get rebound", "Rotate to next offensive player", "Must stop 2 of 3 to leave the hole"],
                 keyPoints: ["Emphasize correct angles and closeouts", "Be second jumper on closeout", "Multiple efforts: closeout then angle to stop drive", "Don't over closeout - allow some space", "KYP - adjust closeout based on personnel", "Goal: only allow contested 2-point attempts"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
                 tags: ["closeouts", "angles", "1v1-defense"]),
        
        DrillItem(name: "2v2 Shell", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "2v2 shell drill focusing on long closeouts, ball-you-man position, and constant movement.",
                 instructions: ["Offensive players start elbow extended", "Defensive players on help line", "Coach tells defenders to chop it up (stance)", "Defenders closeout on command", "Coach passes along perimeter", "Defenders position for ball/help, rush closeouts", "Run for 20 seconds then switch"],
                 keyPoints: ["Ball-you-man position always", "Off ball defender sees ball and man", "Rotate from X man to low man with ball", "Self-correction important", "Easily evaluate player strengths/weaknesses"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 12,
                 tags: ["shell-defense", "closeouts", "positioning"]),
        
        DrillItem(name: "Deflection Drill", category: .defense, difficulty: .beginner,
                 durationMinutes: 5, description: "Zone defense drill building active hands and reading passing angles.",
                 instructions: ["3 offensive players form triangle", "1 defensive player in middle", "Player 1 has ball", "Offensive players pass among themselves", "Offense cannot move or dribble", "Defender attempts to deflect as many passes as possible"],
                 keyPoints: ["Read eyes and shoulders of passer", "Can run for time (:45) or switch on deflection", "Make it passing drill - offense uses fakes", "Can build up: 4v2, 4v3, 5v3, 5v4"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 10,
                 variations: ["Switch on deflection or run for time", "Build to 4v2, 4v3, 5v3, 5v4"],
                 tags: ["zone-defense", "deflections", "anticipation"]),
        
        // MARK: - Breakthrough Basketball Drills (Batch 3)
        DrillItem(name: "Get Back Drill", category: .defense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Full court press drill working on filling the hole and building defensive wall.",
                 instructions: ["Offensive players along baseline with defenders", "Coach passes to any offensive player", "Defender guarding receiver sprints to touch baseline", "In Rambo variation, coach calls out different defender", "Called defender fills hole, keeps ball to outer thirds", "Original defender still touches baseline before playing"],
                 keyPoints: ["Defender must clearly declare the hole", "Communicate through ball screen coverages", "Emphasize non-negotiables throughout", "More ball reversals = more challenging", "Can have two defenders touch baseline for difficulty"],
                 equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 15,
                 variations: ["Rambo variation: coach calls different defender", "Two defenders touch baseline"],
                 tags: ["press-defense", "communication", "transition"]),
        
        DrillItem(name: "1v2 Trapping", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "2-2-1 press drill teaching guards to funnel sideline and second line to set trap.",
                 instructions: ["Player 1 starts with ball on one side", "X1 funnels player 1 up sideline", "X2 positioned near half court same side", "Player 1 tries to split or beat defenders", "X1 and X2 trap just across half court"],
                 keyPoints: ["Good trapping angles and lock feet", "Attack with speed - slow pace allows trap setup", "X2 'dances' (fakes up/back) to create indecision", "Can inbound ball to work on forcing to corner"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["press-defense", "trapping", "2-2-1"]),
        
        DrillItem(name: "3v2 Sideline Trap", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Progression from 1v2 trapping incorporating all 3 levels of press with multiple trap areas.",
                 instructions: ["X1 funnels player 1 up sideline", "X2 dances at half court", "X5 shades ball side on lane line", "Player 5 on ball side wing in forecourt", "As ball approaches half, X1 and X2 trap", "If pass to player 5, X5 can steal or pressure", "X2 turns and sets second trap with X5", "X1 drops to deny reversal"],
                 keyPoints: ["X5 must be sure of steal or stay and trap", "Don't allow baseline drive if trapping with X2", "Multiple trap areas simulated", "Rotations after trap essential"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 12,
                 tags: ["press-defense", "trapping", "rotation"]),
        
        DrillItem(name: "2v1 Tip From Behind", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Builds skill of getting back in play after being beaten and tipping ball from behind.",
                 instructions: ["2 defenders start on elbow", "One offensive player under rim with ball, one at top", "Player 2 passes to player 1 (player 2 out)", "Player 1 speed dribbles to other basket", "X1 and X2 sprint and chase from behind", "Goal: tip ball away before layup", "Only ball side defender attempts tip"],
                 keyPoints: ["Only ball side player tips to minimize fouls", "Other player sprints alongside ready if ball switches", "Offense works speed dribbling and finishing under control"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["recovery", "transition-defense", "tip"]),
        
        DrillItem(name: "Trap To A Tip", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Works multiple traps and sprint mentality transitioning to tip from behind.",
                 instructions: ["Player 1 starts with ball, player 2 under rim", "X1 and X2 trapping player 1", "Player 1 passes to player 2 (X1/X2 can't touch pass)", "Player 1 out of drill", "Player 2 dribbles hard up opposite side to score", "X1 and X2 sprint at good angles to cut off", "If catch player 2, trap along sideline", "If player 2 splits, chase and tip from behind"],
                 keyPoints: ["Good angles when cutting off ball", "Don't end up behind dribbler", "Transition from trap to chase seamlessly"],
                 equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
                 tags: ["press-defense", "trapping", "recovery"]),
        
        DrillItem(name: "Tip From Behind", category: .defense, difficulty: .beginner,
                 durationMinutes: 5, description: "Fundamental drill for any defense teaching proper technique for tipping ball from behind.",
                 instructions: ["Players partner up on baseline", "Offensive player has ball", "Defensive player lines up on dribbling hand side", "Offensive player speed dribbles to other end", "Defensive player tries to tap ball away", "If offense changes hands, wait or run to other side", "Never tip across offensive player's body"],
                 keyPoints: ["Tip with hand next to ball handler (inside hand)", "Tip ball up softly, not down", "Doesn't always feel natural - takes practice", "Tipping up almost never called a foul"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 20,
                 tags: ["fundamentals", "tip", "recovery"]),
        
        DrillItem(name: "Split & Tip", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Works on next right action when ball handler splits the press.",
                 instructions: ["Offense and defense start in corners", "Player 1 has ball", "Player 1 dribbles hard toward middle, splitting X1 and X2", "X1 and X2 sprint and chase from behind", "Goal: tip ball away before player 1 scores", "Only ball side player tips"],
                 keyPoints: ["Tip up on ball, not down", "Tipping down usually called foul", "Don't reach across body"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["press-defense", "recovery", "tip"]),
        
        DrillItem(name: "4v4 Box Middle Drill", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Works on run and jump when ball is dribbled to middle in press.",
                 instructions: ["4 offensive players in box formation", "4 defenders match up with 5th at rim", "5th defender steals deep passes", "Player 1 attacks middle of floor", "Cues X2 and X1 to execute run and jump", "X3, X4, X5 move with ball", "After jump, play is live"],
                 keyPoints: ["Jump on line of next pass", "Forces ball over jumping player", "Increases deflection likelihood", "Slower pass allows rotation time"],
                 equipmentNeeded: ["Basketball"], minPlayers: 9, maxPlayers: 12,
                 tags: ["press-defense", "run-and-jump", "rotation"]),
        
        DrillItem(name: "4v4 Box Sideline Drill", category: .defense, difficulty: .advanced,
                 durationMinutes: 10, description: "Works desired sideline trap outcome in press with proper rotations.",
                 instructions: ["4 offensive players in box formation", "4 defenders match up with 5th at rim", "Player 1 attacks up sideline", "X1 turns and sprints at angle to cut off", "X2 sprints after to close trap", "X3, X4, X5 move with ball", "After initial trap, live play", "Look for turnover or other trap opportunities"],
                 keyPoints: ["Weak side defenders get to midline", "Can work back on skip but can't give up middle", "Don't hug your man on weak side"],
                 equipmentNeeded: ["Basketball"], minPlayers: 9, maxPlayers: 12,
                 tags: ["press-defense", "sideline-trap", "rotation"]),
        
        DrillItem(name: "Guard Overload", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "2-3 zone drill where guards work on relentless rotations covering 3-4 offensive players.",
                 instructions: ["Offensive team: 4 players (point, wings, high post)", "X1 and X2 at guard positions in 2-3 zone", "Player 1 has ball", "Offensive players pass among themselves", "Cannot move, dribble, or shoot", "Defenders rotate, always deter high post pass"],
                 keyPoints: ["Move on flight of pass", "Stay in stance at all times", "Read eyes and shoulders of passer", "Play with hands up to make passes harder"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 10,
                 tags: ["zone-defense", "2-3-zone", "guard-play"]),
        
        DrillItem(name: "Rebound By Numbers", category: .defense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Zone rebounding drill teaching defenders to quickly identify and box out assignments.",
                 instructions: ["5 offensive players beyond 3-point line, numbered 1-5", "2 defensive players in paint", "Coach has ball", "Coach shoots and calls two numbers", "Called players go to rebound", "X1 and X2 must find and box out those players", "Play through rebound"],
                 keyPoints: ["Defenders must communicate to avoid same player", "Can play through rebound or play live until score", "To increase difficulty, allow offense to move before shot", "Can do with 3 offensive players and 1 defender"],
                 equipmentNeeded: ["Basketball"], minPlayers: 7, maxPlayers: 12,
                 variations: ["3 offense, 1 defense", "Allow offense to move before shot"],
                 tags: ["zone-defense", "rebounding", "box-out"]),
        
        DrillItem(name: "Curl Cut Drill", category: .offense, difficulty: .beginner,
                 durationMinutes: 8, description: "Works on curl cuts off screens with proper timing and shooting.",
                 instructions: ["Player 1 passes to player 2", "Player 3 curls off player 1's screen", "Receives pass from coach on left wing", "Player 3 curls when defender trailing", "Player 1 cuts to top for shot from player 2", "Rotate: 1 to 3's line, 2 to 1's line, 3 to 2's line"],
                 keyPoints: ["Follow pass for step before screening", "Step toward baseline for better angle", "Curl when defender is trailing"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["cutting", "screens", "curls"]),
        
        DrillItem(name: "Flare Cut Drill", category: .offense, difficulty: .beginner,
                 durationMinutes: 8, description: "Works on flare cuts off screens with slip and shooting action.",
                 instructions: ["Player 1 passes to player 2, receives flare screen from player 3", "Player 3 slips screen to receive pass from coach", "Player 1 flares to corner for shot from player 2", "Rotate: 1 to 3's line, 2 to 1's line, 3 passes then to 2's line"],
                 keyPoints: ["Proper flare angle", "Slip screen timing", "Shot ready on flare"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["cutting", "screens", "flares"]),
        
        DrillItem(name: "Kick Up Drill", category: .offense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Works on attacking basket with intent and kicking to free throw line extended.",
                 instructions: ["Player 1 attacks basket", "Player 2 moves from corner to FT line extended", "Player 1 makes positive pass after player 2 moves behind", "Player 2 shoots"],
                 keyPoints: ["Attack with intent to score/draw foul", "Sprint step not slide to create space faster", "Force defender through passer to closeout", "Wait for positive pass timing"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 12,
                 tags: ["drive-and-kick", "penetration", "spacing"]),
        
        DrillItem(name: "Kick Back Drill", category: .offense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Works on kick back pass based on attack angle, different from kick up.",
                 instructions: ["Player 1 attacks basket", "Ball side wing (player 4) finds window for pass", "Off guard fills behind 6-8 feet from attacker", "Player 1 makes positive pass to player 4", "Cutters fill open areas"],
                 keyPoints: ["Different from kick up based on angle", "Don't do negative kick-back (same side as help)", "Force defender through passer to closeout", "Be effective with positive spacing"],
                 equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 12,
                 tags: ["drive-and-kick", "penetration", "spacing"]),
        
        DrillItem(name: "2 Man Hammer Pass", category: .offense, difficulty: .intermediate,
                 durationMinutes: 8, description: "Works on hammer action popularized by Spurs to generate corner three.",
                 instructions: ["Player 1 attacks baseline", "Player 2 moves to corner in player 1's line of sight", "Player 1 passes to player 2 for corner three", "Player 2 shoots, player 1 relocates for shot from coach"],
                 keyPoints: ["Line up directly in attacker's sight line", "Common NBA action", "Generates open corner threes"],
                 equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 12,
                 tags: ["hammer", "corner-three", "spacing"]),
        
        DrillItem(name: "Handoff & Help Drill", category: .offense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Works on zoom action reads in 3v3 with focus on getting downhill and reading help.",
                 instructions: ["Player 1 at top with ball and defender", "Player 2 in corner with defender", "Player 3 opposite corner with defender", "Chair where screen would occur", "Player 1 dribbles at chair, player 2 comes for DHO", "Once player 2 gets ball, live 3v3"],
                 keyPoints: ["Read where help defender (X3) is positioned", "Spot up player stays low, hands/feet ready", "Player 2 positions for scoring opportunity", "Can start going both ways for variety", "Can do 4v4 with full zoom action"],
                 equipmentNeeded: ["Basketball", "Chair"], minPlayers: 6, maxPlayers: 12,
                 variations: ["Start drill going both ways", "4v4 with full zoom action"],
                 tags: ["zoom", "dribble-handoff", "reads"]),
        
        DrillItem(name: "Zoom Reads Drill", category: .offense, difficulty: .advanced,
                 durationMinutes: 12, description: "Full zoom action in 3v3 incorporating all reads and reactions.",
                 instructions: ["Player 1 at top with ball and defender", "Player 2 on wing with defender", "Player 3 in corner with defender", "Player 2 screens for player 3 as player 1 dribbles at player 2", "Live 3v3 with opposite lane line as out of bounds"],
                 keyPoints: ["Focus on reads/reactions", "Get downhill on dribble handoffs", "Quick hard cuts reading zoom", "Can start with ball on opposite wing for timing", "Can predetermine reads when teaching", "Challenge with specific player must shoot"],
                 equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 12,
                 variations: ["Start with ball on opposite wing", "Predetermine offensive reads", "Specific player must get shot"],
                 tags: ["zoom", "reads", "decision-making"]),
        
        DrillItem(name: "Press Breaker Drill", category: .offense, difficulty: .intermediate,
                 durationMinutes: 10, description: "Works on breaking press with numerical disadvantage to prepare for game pressure.",
                 instructions: ["Use 3v2, 4v3, or 7v5 variations", "Offense takes ball out of bounds", "Offense tries to break press and score", "Can reset at half court if limited on time", "Vary press: full denial, full court, 3/4 court"],
                 keyPoints: ["Practice against more defenders than game", "If can break 7 defenders, can break most pressure", "Adjust press type to what you'll face", "Simple but extremely effective concept"],
                 equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 12,
                 variations: ["3v2, 4v3, or 7v5", "Full denial, full court, or 3/4 court press"],
                 tags: ["press-break", "pressure", "ball-handling"])
    ]
}

// MARK: - Court Scheme Models for Basketball Lab

/// Represents a player marker on the court
struct CourtPlayer: Identifiable, Codable, Hashable {
    let id: UUID
    var position: CGPoint  // Normalized 0-1 coordinates
    var team: CourtTeam
    var number: Int?
    var label: String?
    var hasBall: Bool
    
    init(id: UUID = UUID(), position: CGPoint, team: CourtTeam = .offense, number: Int? = nil, label: String? = nil, hasBall: Bool = false) {
        self.id = id
        self.position = position
        self.team = team
        self.number = number
        self.label = label
        self.hasBall = hasBall
    }
}

enum CourtTeam: String, Codable, CaseIterable {
    case offense, defense
    
    var color: String {
        switch self {
        case .offense: return "white"
        case .defense: return "yellow"
        }
    }
    
    var displayName: String {
        switch self {
        case .offense: return "Offense"
        case .defense: return "Defense"
        }
    }
}

/// Represents a movement arrow on the court
struct CourtMovement: Identifiable, Codable, Hashable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var waypoints: [CGPoint]  // Intermediate points for bending the path
    var movementType: MovementType
    var pathStyle: PathStyle  // Sharp corners or curved
    var playerId: UUID?  // Optional link to player
    
    init(id: UUID = UUID(), startPoint: CGPoint, endPoint: CGPoint, waypoints: [CGPoint] = [], movementType: MovementType = .run, pathStyle: PathStyle = .sharp, playerId: UUID? = nil) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.waypoints = waypoints
        self.movementType = movementType
        self.pathStyle = pathStyle
        self.playerId = playerId
    }
}

enum PathStyle: String, Codable, CaseIterable {
    case sharp, curved
    
    var displayName: String {
        switch self {
        case .sharp: return "Sharp"
        case .curved: return "Curved"
        }
    }
}

enum MovementType: String, Codable, CaseIterable {
    case run, dribble, pass, screen, cut, drawArrow, drawFlat, drawCurved
    
    var displayName: String {
        switch self {
        case .run: return "Run"
        case .dribble: return "Dribble"
        case .pass: return "Pass"
        case .screen: return "Screen"
        case .cut: return "Cut"
        case .drawArrow: return "Arrow"
        case .drawFlat: return "Line"
        case .drawCurved: return "Curve"
        }
    }
    
    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .dribble: return "hand.point.down"
        case .pass: return "arrow.right"
        case .screen: return "rectangle.portrait"
        case .cut: return "scissors"
        case .drawArrow: return "arrow.up.right"
        case .drawFlat: return "line.diagonal"
        case .drawCurved: return "scribble"
        }
    }
    
    var lineStyle: String {
        switch self {
        case .run: return "solid"
        case .dribble: return "wavy"
        case .pass: return "dashed"
        case .screen: return "thick"
        case .cut: return "zigzag"
        case .drawArrow: return "solid"
        case .drawFlat: return "solid"
        case .drawCurved: return "solid"
        }
    }
    
    var isDrawType: Bool {
        switch self {
        case .drawArrow, .drawFlat, .drawCurved: return true
        default: return false
        }
    }
}

/// A single frame/step in a play sequence
struct CourtFrame: Identifiable, Codable, Hashable {
    let id: UUID
    var players: [CourtPlayer]
    var movements: [CourtMovement]
    var notes: String?
    var order: Int
    
    init(id: UUID = UUID(), players: [CourtPlayer] = [], movements: [CourtMovement] = [], notes: String? = nil, order: Int = 0) {
        self.id = id
        self.players = players
        self.movements = movements
        self.notes = notes
        self.order = order
    }
}

/// A complete court scheme (play or drill diagram)
struct CourtScheme: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var schemeType: SchemeType
    var frames: [CourtFrame]
    var description: String?
    var tags: [String]
    var isFavorite: Bool
    var drillId: UUID?  // Optional link to a drill
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, schemeType: SchemeType = .play, frames: [CourtFrame] = [], 
         description: String? = nil, tags: [String] = [], isFavorite: Bool = false, drillId: UUID? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.schemeType = schemeType
        self.frames = frames.isEmpty ? [CourtFrame(order: 0)] : frames
        self.description = description
        self.tags = tags
        self.isFavorite = isFavorite
        self.drillId = drillId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var frameCount: Int { frames.count }
    var playerCount: Int { frames.first?.players.count ?? 0 }
}

enum SchemeType: String, Codable, CaseIterable {
    case play, drill, setpiece, defense
    
    var displayName: String {
        switch self {
        case .play: return "Play"
        case .drill: return "Drill"
        case .setpiece: return "Set Piece"
        case .defense: return "Defense"
        }
    }
    
    var icon: String {
        switch self {
        case .play: return "sportscourt"
        case .drill: return "figure.basketball"
        case .setpiece: return "target"
        case .defense: return "shield"
        }
    }
}
