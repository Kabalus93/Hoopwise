import Foundation

// MARK: - Elite Drill Library
//
// A curated, age-tagged drill bank seeded from publicly documented coaching
// frameworks. Each drill carries source attribution via `source:*` tag so
// the lineage is visible in the library and the plan generator can prefer
// attributed drills over generic library content.
//
// Sources used (paraphrased, never copied verbatim):
//   • FEB / Spanish Basketball Federation youth progression docs (`source:feb`)
//   • FIBA Development guidelines (`source:fiba`)
//   • NBA Player Development principles (`source:nba`)
//   • Coach's Clipboard / classic team play references (`source:clipboard`)
//
// Tag conventions consumed by `DrillProfile`:
//   • Age:       u6 / u8 / u10 / u12 / u14 / u16 / u18 / adult (multiple OK)
//   • Focus:     shooting · ball-handling · passing · defense ·
//                conditioning · team-play · game-prep · recovery
//   • Intensity: intensity:low | intensity:medium | intensity:high
//   • Format:    format:individual | format:small-group | format:team |
//                format:full-court (or aliases 1v1, 3v3, 5v5, scrimmage)
//
// Update guide: stay disciplined with tags so the generator surfaces drills
// well. The plan generator is purely deterministic — better tags = better
// plans, no model retraining required.

extension DrillItem {

    static let eliteSamples: [DrillItem] = {
        var all: [DrillItem] = []
        all.append(contentsOf: shootingElite)
        all.append(contentsOf: ballHandlingElite)
        all.append(contentsOf: passingElite)
        all.append(contentsOf: defenseElite)
        all.append(contentsOf: conditioningElite)
        all.append(contentsOf: warmupElite)
        all.append(contentsOf: cooldownElite)
        all.append(contentsOf: teamPlayElite)
        return all
    }()

    // MARK: - Shooting (FEB / NBA Player Dev paraphrased)

    private static let shootingElite: [DrillItem] = [
        DrillItem(
            name: "1-2 Step Form Series",
            category: .shooting, difficulty: .beginner, durationMinutes: 8,
            description: "Foundational 1-2 step shooting progression — the FEB minibasket entry to game-speed shooting.",
            instructions: [
                "Start three feet from the rim, ball at the hip",
                "Step in 1-2 (inside-foot first), rise into shot",
                "10 makes, take one step back, repeat to free-throw line"
            ],
            keyPoints: ["Inside foot first", "Eyes on the rim through release", "Hold follow-through until ball lands"],
            equipmentNeeded: ["Basketball", "Hoop"], minPlayers: 1, maxPlayers: 4,
            tags: ["u6", "u8", "u10", "shooting", "fundamentals", "intensity:low", "format:individual", "source:feb"]
        ),
        DrillItem(
            name: "5-Spot Catch & Shoot",
            category: .shooting, difficulty: .intermediate, durationMinutes: 12,
            description: "Mid-range to three-point catch-and-shoot rhythm at five spots: corners, wings, top of key.",
            instructions: [
                "Coach or partner passes; shooter sprints to spot, squares, shoots",
                "Make 3 from each spot before moving",
                "Track time and total makes — chase a personal best"
            ],
            keyPoints: ["Toes squared on catch", "Hands ready before catch", "No travel — pivot inside foot"],
            equipmentNeeded: ["Basketball", "Hoop"], minPlayers: 2, maxPlayers: 4,
            tags: ["u12", "u14", "u16", "u18", "shooting", "intensity:medium", "format:small-group", "source:feb"]
        ),
        DrillItem(
            name: "NBA Range Triple Threat",
            category: .shooting, difficulty: .advanced, durationMinutes: 15,
            description: "Triple-threat read into shot, drive, or pull-up — emphasizing decisiveness from NBA range.",
            instructions: [
                "Receive pass at NBA three-point line in triple threat",
                "Coach signals: 'shot' / 'drive' / 'pull-up'",
                "Execute one move per rep, reset; rotate three spots"
            ],
            keyPoints: ["Low stance, ball protected", "Read on the catch, not on the move", "Finish or shoot off two feet"],
            equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 4,
            tags: ["u16", "u18", "adult", "shooting", "ball-handling", "intensity:medium", "format:small-group", "source:nba"]
        ),
        DrillItem(
            name: "Pull-Up off Pin-Down",
            category: .shooting, difficulty: .advanced, durationMinutes: 12,
            description: "Curl or fade off a pin-down screen — pro-level shot creation off off-ball action.",
            instructions: [
                "Screener sets pin-down at the elbow",
                "Shooter reads defender — curl tight if trailed, fade if shot",
                "Make 8 of each read before switching roles"
            ],
            keyPoints: ["Set up the cut — sell the V-cut first", "Shoulders square on catch", "Use one-dribble rip if defender recovers"],
            equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 4,
            tags: ["u14", "u16", "u18", "adult", "shooting", "team-play", "intensity:medium", "format:small-group", "source:nba"]
        ),
        DrillItem(
            name: "Beat the Pro: 100",
            category: .shooting, difficulty: .advanced, durationMinutes: 15,
            description: "Self-competing scoring game — accumulate 100 points across spots, harder shots worth more.",
            instructions: [
                "Layup = 1, mid-range = 2, three = 3, contested three = 5",
                "Reach 100 within the timer, missed shots subtract 1",
                "Track best time; rotate cohort to a fresh spot every 60s"
            ],
            keyPoints: ["No bailout shots near the rim", "Reset to triple threat every catch", "Talk yourself through pace"],
            equipmentNeeded: ["Basketball", "Stopwatch"], minPlayers: 1, maxPlayers: 6,
            tags: ["u14", "u16", "u18", "adult", "shooting", "conditioning", "intensity:high", "format:individual", "source:nba"]
        ),
        DrillItem(
            name: "Free Throw Pressure",
            category: .shooting, difficulty: .intermediate, durationMinutes: 8,
            description: "Conditioning + pressure free throws — replicates end-of-game fatigue.",
            instructions: [
                "Sprint to half-court and back",
                "Step to the line, shoot 2 free throws",
                "Repeat for 5 rounds, 10 attempts total"
            ],
            keyPoints: ["Same routine every shot", "Deep breath before release", "Track makes — chase 8/10"],
            equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 6,
            tags: ["u12", "u14", "u16", "u18", "adult", "shooting", "conditioning", "intensity:high", "format:individual", "source:fiba"]
        ),
        DrillItem(
            name: "1-Dribble Pull-Up Series",
            category: .shooting, difficulty: .intermediate, durationMinutes: 10,
            description: "Catch, attack the close-out with one dribble, rise into a balanced pull-up.",
            instructions: [
                "Start at the wing, partner passes from top",
                "Right hand 1-dribble pull-up (5 makes), left hand (5 makes)",
                "Add a counter step-back on every third rep"
            ],
            keyPoints: ["First dribble out of stance", "Two feet on rise — no fadeaway", "Shoulders square through release"],
            equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 4,
            tags: ["u14", "u16", "u18", "adult", "shooting", "ball-handling", "intensity:medium", "format:small-group", "source:nba"]
        ),
        DrillItem(
            name: "Curl-Fade-Straight Read",
            category: .shooting, difficulty: .advanced, durationMinutes: 12,
            description: "Three-read shooting off a baseline screen — coaches' clipboard staple for wing scorers.",
            instructions: [
                "Coach trails as the defender; signals defensive positioning",
                "Shooter reads: curl tight, fade to corner, or straight cut",
                "Hit the read, take the shot, then reset"
            ],
            keyPoints: ["Read at the screen, not before", "Hands ready before the catch", "Square shoulders to rim on every option"],
            equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 5,
            tags: ["u16", "u18", "adult", "shooting", "team-play", "intensity:medium", "format:small-group", "source:clipboard"]
        ),
    ]

    // MARK: - Ball Handling

    private static let ballHandlingElite: [DrillItem] = [
        DrillItem(
            name: "Pound Series — Stationary",
            category: .skills, difficulty: .beginner, durationMinutes: 6,
            description: "Two-ball pound series for hand strength and rhythm. NBA pre-practice staple.",
            instructions: [
                "Two balls, pound at hip height (30s)",
                "Pound waist height (30s), shoulder height (30s)",
                "Alternating hands, then opposite rhythm"
            ],
            keyPoints: ["Eyes up", "Fingertip control — no palming", "Push through the floor"],
            equipmentNeeded: ["2 basketballs"], minPlayers: 1,
            tags: ["u10", "u12", "u14", "u16", "u18", "adult", "ball-handling", "intensity:low", "format:individual", "source:nba"]
        ),
        DrillItem(
            name: "Cone Combo Series",
            category: .skills, difficulty: .intermediate, durationMinutes: 12,
            description: "Five cones, five attack moves — the staple combo workout used across FEB academies.",
            instructions: [
                "Set five cones in a line, six feet apart",
                "Combo at each: 1) crossover, 2) between legs, 3) behind back, 4) hesitation, 5) in-out cross",
                "Finish with a layup or pull-up at the rim"
            ],
            keyPoints: ["Change pace at every cone", "Eyes up — peripheral the floor", "Low base on every change of direction"],
            equipmentNeeded: ["Basketball", "5 cones"], minPlayers: 1, maxPlayers: 4,
            tags: ["u12", "u14", "u16", "u18", "ball-handling", "intensity:medium", "format:individual", "source:feb"]
        ),
        DrillItem(
            name: "2-Ball Tennis-Ball React",
            category: .skills, difficulty: .advanced, durationMinutes: 8,
            description: "Two-ball dribble plus tennis-ball toss — vision, hand-eye, and dual-task coordination.",
            instructions: [
                "Player dribbles two balls; partner stands six feet away with a tennis ball",
                "Partner tosses tennis ball randomly left or right",
                "Player catches with the off-hand without losing the dribble"
            ],
            keyPoints: ["Tight, low dribble", "Eyes scan partner, not the ball", "Reset rhythm after every catch"],
            equipmentNeeded: ["2 basketballs", "Tennis ball"], minPlayers: 2, maxPlayers: 2,
            tags: ["u14", "u16", "u18", "adult", "ball-handling", "intensity:medium", "format:individual", "source:nba"]
        ),
        DrillItem(
            name: "Full-Court Zig-Zag",
            category: .skills, difficulty: .intermediate, durationMinutes: 8,
            description: "Change-of-direction drill — drive, plant, change hands, drive again. FIBA development standard.",
            instructions: [
                "Start at baseline, attack to free-throw line",
                "Hard plant, crossover, attack to half-court",
                "Repeat across full court — finish at rim"
            ],
            keyPoints: ["Plant outside foot, drop hips", "Push off — don't bounce", "Eyes up the entire trip"],
            equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 6,
            tags: ["u10", "u12", "u14", "u16", "u18", "ball-handling", "conditioning", "intensity:high", "format:individual", "source:fiba"]
        ),
        DrillItem(
            name: "Chair Read Attack",
            category: .skills, difficulty: .advanced, durationMinutes: 10,
            description: "Read drill — chair represents a defender, work different attack patterns based on coach call.",
            instructions: [
                "Place chair at top of key as 'defender'",
                "Coach calls: 'high', 'low', 'split' — attack accordingly",
                "Finish with a balanced pull-up or layup"
            ],
            keyPoints: ["Read on the catch", "Get hip past chair before going up", "Counter immediately if defender 'recovers'"],
            equipmentNeeded: ["Basketball", "Chair or cone"], minPlayers: 1, maxPlayers: 3,
            tags: ["u14", "u16", "u18", "adult", "ball-handling", "shooting", "intensity:medium", "format:individual", "source:nba"]
        ),
        DrillItem(
            name: "Tight-Space Handle",
            category: .skills, difficulty: .advanced, durationMinutes: 8,
            description: "Confined-space dribble drill — operate inside a 4x4 box without losing the ball.",
            instructions: [
                "Tape or cone a 4x4 ft box on the floor",
                "Stay inside the box, run all combo moves for 60 seconds",
                "Two reps per hand"
            ],
            keyPoints: ["Hesitations and pivots, not just speed", "Protect with off-arm", "Stay low — knees over toes"],
            equipmentNeeded: ["Basketball", "Tape or cones"], minPlayers: 1,
            tags: ["u14", "u16", "u18", "adult", "ball-handling", "intensity:medium", "format:individual", "source:nba"]
        ),
    ]

    // MARK: - Passing

    private static let passingElite: [DrillItem] = [
        DrillItem(
            name: "Star Passing",
            category: .offense, difficulty: .beginner, durationMinutes: 8,
            description: "Five-spot passing star — pass and follow your pass, FEB minibasket fundamental.",
            instructions: [
                "Five players spaced in a star around the key",
                "Pass and follow to the spot you passed to",
                "Switch direction every 30 seconds"
            ],
            keyPoints: ["Two-handed chest pass", "Step to your target", "Call the receiver's name"],
            equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 5,
            tags: ["u8", "u10", "u12", "passing", "team-play", "intensity:low", "format:small-group", "source:feb"]
        ),
        DrillItem(
            name: "Monkey-in-the-Middle Pressure",
            category: .offense, difficulty: .intermediate, durationMinutes: 8,
            description: "Two passers, one defender; pressure passing under contest.",
            instructions: [
                "Passers 12 ft apart, defender between them",
                "Make 10 successful passes — bounce, chest, overhead mix",
                "Defender swaps with passer who turns it over"
            ],
            keyPoints: ["Pivot and protect on catch", "Pass-fake before the real pass", "No telegraphing"],
            equipmentNeeded: ["Basketball"], minPlayers: 3, maxPlayers: 3,
            tags: ["u10", "u12", "u14", "passing", "defense", "intensity:medium", "format:small-group", "source:fiba"]
        ),
        DrillItem(
            name: "3-on-2 Outlet Break",
            category: .offense, difficulty: .advanced, durationMinutes: 12,
            description: "Transition outlet → fill lanes → finish in 4 passes or fewer. FIBA fast-break framework.",
            instructions: [
                "Defender misses; rebounder outlets to wing",
                "Lanes fill: middle, opposite wing trailers",
                "Finish at the rim or kick out for a corner three"
            ],
            keyPoints: ["Outlet to the sideline, not the middle", "Run wide; sprint to spots", "Pass ahead — don't dribble unless free"],
            equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 6,
            tags: ["u12", "u14", "u16", "u18", "adult", "passing", "team-play", "conditioning", "intensity:high", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "Skip-Pass Closeout",
            category: .offense, difficulty: .intermediate, durationMinutes: 10,
            description: "Practice the skip pass against a recovering defender — punishes overcommitted help.",
            instructions: [
                "Wing dribbles middle to draw help",
                "Skip cross-court to weak-side shooter",
                "Shooter rises into shot before closeout arrives"
            ],
            keyPoints: ["Throw skip with one hand off the dribble", "Shooter shows hands early", "Closeout high → drive baseline"],
            equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 6,
            tags: ["u14", "u16", "u18", "adult", "passing", "shooting", "team-play", "intensity:medium", "format:small-group", "source:clipboard"]
        ),
        DrillItem(
            name: "Pocket-Pass PnR Read",
            category: .offense, difficulty: .advanced, durationMinutes: 12,
            description: "Pick-and-roll pocket-pass timing — the read for a roller against a drop coverage.",
            instructions: [
                "Ball-handler comes off ball-screen against drop coverage",
                "Reject early if hedge; pocket-pass to roller against drop",
                "Roller reads: lob if vacated rim, shot if mid-range vacated"
            ],
            keyPoints: ["Hit the pocket below the screener's hip", "Two-hand catch on the short roll", "Roller stays patient — don't sprint past the help"],
            equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 6,
            tags: ["u16", "u18", "adult", "passing", "team-play", "game-prep", "intensity:medium", "format:small-group", "source:nba"]
        ),
    ]

    // MARK: - Defense

    private static let defenseElite: [DrillItem] = [
        DrillItem(
            name: "Stance & Slide Ladder",
            category: .defense, difficulty: .beginner, durationMinutes: 6,
            description: "Defensive footwork ladder — stance, slide, drop-step, recover. FIBA youth foundation.",
            instructions: [
                "Down in stance — chest up, hips low",
                "Slide left 3 steps, drop-step, slide right 3, drop-step",
                "Continue for 4 rounds without rising"
            ],
            keyPoints: ["No bouncing — slide flat", "Active hands", "Chest stays vertical"],
            equipmentNeeded: [], minPlayers: 1, maxPlayers: 12,
            tags: ["u8", "u10", "u12", "defense", "conditioning", "intensity:medium", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "Closeout Contest Game",
            category: .defense, difficulty: .intermediate, durationMinutes: 10,
            description: "Sprint-then-balance closeouts — stop the catch-and-shoot but don't bite the pump fake.",
            instructions: [
                "Defender starts at the paint",
                "Coach passes to shooter at three-point line",
                "Defender sprints, breaks down, contests with high hand"
            ],
            keyPoints: ["Last 3 steps are short choppy", "Don't leave feet on a fake", "Hand high, contest with the inside arm"],
            equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 4,
            tags: ["u12", "u14", "u16", "u18", "adult", "defense", "intensity:medium", "format:small-group", "source:nba"]
        ),
        DrillItem(
            name: "Shell Drill — 4-on-4",
            category: .defense, difficulty: .advanced, durationMinutes: 15,
            description: "Half-court shell — the canonical team defense teaching tool. Pass-and-react rules.",
            instructions: [
                "4 offense around the perimeter, 4 on defense",
                "Ball moves on coach's call; defense rotates: jump-to-ball, deny, weak-help",
                "Add screen reads after 5 minutes"
            ],
            keyPoints: ["Talk on every pass", "Hand in the lane on adjacent denial", "Weak-side splits the gap"],
            equipmentNeeded: ["Basketball"], minPlayers: 8, maxPlayers: 10,
            tags: ["u14", "u16", "u18", "adult", "defense", "team-play", "intensity:medium", "format:team", "source:clipboard"]
        ),
        DrillItem(
            name: "Box-Out Battle",
            category: .defense, difficulty: .intermediate, durationMinutes: 8,
            description: "Two-player rebounding — earn position, get the ball, score in the paint.",
            instructions: [
                "Pair up at the elbow",
                "Coach takes a shot — first to box out wins position",
                "Defender must rebound and outlet, offense must score on putback"
            ],
            keyPoints: ["Hit first — initiate contact", "Find then locate the ball", "Two-hand the rebound at chin level"],
            equipmentNeeded: ["Basketball"], minPlayers: 2, maxPlayers: 8,
            tags: ["u12", "u14", "u16", "u18", "adult", "defense", "intensity:high", "format:small-group", "source:fiba"]
        ),
        DrillItem(
            name: "Help-and-Recover",
            category: .defense, difficulty: .advanced, durationMinutes: 12,
            description: "On-ball drive plus weak-side help-and-recover — train the gap defender.",
            instructions: [
                "Wing drives baseline against on-ball defender",
                "Weak-side help defender stunts to body up the driver",
                "Driver kicks to the defender's man — defender must close out hard"
            ],
            keyPoints: ["Help on time, not too early", "Two feet down before recovering", "Closeout with hand in the line of the shot"],
            equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 6,
            tags: ["u14", "u16", "u18", "adult", "defense", "team-play", "intensity:medium", "format:small-group", "source:nba"]
        ),
        DrillItem(
            name: "Charge / Block Read",
            category: .defense, difficulty: .advanced, durationMinutes: 8,
            description: "Drive into help — defender reads charge angle vs vertical contest. Physical, supervised drill.",
            instructions: [
                "Driver attacks from the wing toward the rim",
                "Help defender reads angle: outside line = charge, inline = vertical contest",
                "Coach grades the read on every rep"
            ],
            keyPoints: ["Charge = two feet set, chest takes contact", "Block = vertical, no swipe", "Always finish the play — no quitting on a foul call"],
            equipmentNeeded: ["Basketball", "Pad (optional)"], minPlayers: 3, maxPlayers: 6,
            tags: ["u16", "u18", "adult", "defense", "intensity:high", "format:small-group", "source:nba"]
        ),
    ]

    // MARK: - Conditioning

    private static let conditioningElite: [DrillItem] = [
        DrillItem(
            name: "17s",
            category: .conditioning, difficulty: .advanced, durationMinutes: 6,
            description: "Sideline-to-sideline 17 touches under one minute — Spurs-era staple.",
            instructions: [
                "Start at sideline, sprint to opposite sideline",
                "17 sideline touches in under 60 seconds (under 70 for youth)",
                "Two rounds with 90-second rest"
            ],
            keyPoints: ["Touch every line", "Drive arms — sprint mechanics", "Don't pace — go all out"],
            equipmentNeeded: [], minPlayers: 1, maxPlayers: 12,
            tags: ["u14", "u16", "u18", "adult", "conditioning", "intensity:high", "format:team", "source:nba"]
        ),
        DrillItem(
            name: "Tabata Lateral",
            category: .conditioning, difficulty: .intermediate, durationMinutes: 5,
            description: "20s on, 10s off — eight rounds of lateral defensive sliding. Anaerobic capacity builder.",
            instructions: [
                "Set up 8 ft cone gates",
                "20s max-effort lateral slides between cones, 10s rest",
                "8 rounds total — track total slides"
            ],
            keyPoints: ["Stay low — no rising on rest", "Touch the floor at each cone", "Push off the outside foot"],
            equipmentNeeded: ["Cones", "Stopwatch"], minPlayers: 1, maxPlayers: 12,
            tags: ["u12", "u14", "u16", "u18", "adult", "conditioning", "defense", "intensity:high", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "Make-It-Take-It Sprint",
            category: .conditioning, difficulty: .intermediate, durationMinutes: 8,
            description: "Combine shooting and conditioning — make 5 spots, sprint full court between misses.",
            instructions: [
                "Five spots around the arc",
                "Make a shot at each — miss = sprint full court and back",
                "Total time tracked; chase a personal record"
            ],
            keyPoints: ["Pace yourself early", "Sprint mechanics on penalties — no jogging", "Reset to good form on the next shot"],
            equipmentNeeded: ["Basketball"], minPlayers: 1, maxPlayers: 6,
            tags: ["u12", "u14", "u16", "u18", "adult", "conditioning", "shooting", "intensity:high", "format:individual", "source:fiba"]
        ),
        DrillItem(
            name: "Continuous 3-on-2 Break",
            category: .conditioning, difficulty: .advanced, durationMinutes: 12,
            description: "Non-stop 3-on-2 transitions — every defensive stop becomes the next break. NBA conditioning standard.",
            instructions: [
                "3 attack, 2 defend; trailer joins after first shot",
                "Stop = outlet and run the other way",
                "Run for full duration — score, switch, sprint"
            ],
            keyPoints: ["Sprint outlets — don't walk after a make", "Spacing wide on the break", "Defenders communicate: 'ball', 'I got two'"],
            equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 10,
            tags: ["u14", "u16", "u18", "adult", "conditioning", "team-play", "intensity:high", "format:team", "source:nba"]
        ),
        DrillItem(
            name: "Box Jump Triplet",
            category: .conditioning, difficulty: .intermediate, durationMinutes: 6,
            description: "Lower-body power — three sets of vertical jumps with controlled landings.",
            instructions: [
                "Box at moderate height",
                "10 box jumps, focus on soft landing",
                "3 sets, 60s rest between"
            ],
            keyPoints: ["Pause on top — fully extend", "Land with knees over toes, no valgus", "Step down — never jump down"],
            equipmentNeeded: ["Plyo box"], minPlayers: 1, maxPlayers: 6,
            tags: ["u14", "u16", "u18", "adult", "conditioning", "intensity:high", "format:individual", "source:nba"]
        ),
    ]

    // MARK: - Warmup

    private static let warmupElite: [DrillItem] = [
        DrillItem(
            name: "RAMP Warmup",
            category: .warmup, difficulty: .beginner, durationMinutes: 10,
            description: "Raise – Activate – Mobilize – Potentiate. FIBA-recommended athlete prep.",
            instructions: [
                "RAISE: 2 min light jog or jump rope",
                "ACTIVATE: glute bridges, banded walks, scap pull-aparts",
                "MOBILIZE: world's greatest stretch, hip openers, ankle rocks",
                "POTENTIATE: 3 reps of 5 broad jumps + 5 vertical hops"
            ],
            keyPoints: ["Increase intensity each phase", "Quality over quantity", "Skip phases at your own risk"],
            equipmentNeeded: ["Resistance band (optional)"], minPlayers: 1, maxPlayers: 20,
            tags: ["u10", "u12", "u14", "u16", "u18", "adult", "conditioning", "intensity:low", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "Layup Lines + Form Shooting",
            category: .warmup, difficulty: .beginner, durationMinutes: 8,
            description: "Two-lane layup lines plus form-shooting intervals — gets the ball moving early.",
            instructions: [
                "Two lines: shooter / rebounder",
                "First 4 minutes: alternating-side layups",
                "Last 4 minutes: form-shooting close to rim, both hands"
            ],
            keyPoints: ["Pass with two hands at chest", "Strong rebound — no soft hands", "Switch lines every minute"],
            equipmentNeeded: ["Basketball"], minPlayers: 4, maxPlayers: 12,
            tags: ["u8", "u10", "u12", "u14", "shooting", "intensity:low", "format:team", "source:feb"]
        ),
        DrillItem(
            name: "Dynamic Movement Prep",
            category: .warmup, difficulty: .beginner, durationMinutes: 7,
            description: "Full-court dynamic sequence — no equipment, every player can do it.",
            instructions: [
                "High-knees → butt kicks → carioca",
                "Skips for height → skips for distance",
                "Walking lunge with rotation → inchworm to push-up"
            ],
            keyPoints: ["Big arms on every movement", "Don't rush — quality over speed", "Add backwards reps"],
            equipmentNeeded: [], minPlayers: 1, maxPlayers: 20,
            tags: ["u8", "u10", "u12", "u14", "u16", "u18", "adult", "conditioning", "intensity:low", "format:team", "source:fiba"]
        ),
    ]

    // MARK: - Cooldown / Recovery

    private static let cooldownElite: [DrillItem] = [
        DrillItem(
            name: "Static Stretch Circuit",
            category: .cooldown, difficulty: .beginner, durationMinutes: 8,
            description: "Five-minute total-body static stretch — hold each position 30 seconds.",
            instructions: [
                "Quad stretch — 30s each side",
                "Pigeon — 30s each side",
                "Hamstring — 30s each side",
                "Pec stretch in doorway — 30s",
                "Child's pose — 30s"
            ],
            keyPoints: ["Breathe through each hold", "No bouncing — sustained tension", "Skip any painful position"],
            equipmentNeeded: [], minPlayers: 1, maxPlayers: 20,
            tags: ["u8", "u10", "u12", "u14", "u16", "u18", "adult", "recovery", "intensity:low", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "Foam-Roller Reset",
            category: .cooldown, difficulty: .beginner, durationMinutes: 6,
            description: "Self-myofascial release — quads, IT band, glutes, calves. Pro-level recovery basic.",
            instructions: [
                "60s on each: quads, IT band, glutes, calves",
                "Slow rolls — pause on tight spots for 10s",
                "Finish with diaphragmatic breathing for one minute"
            ],
            keyPoints: ["Pressure should feel like a 6/10", "Breathe through the discomfort", "Hydrate immediately after"],
            equipmentNeeded: ["Foam roller"], minPlayers: 1, maxPlayers: 6,
            tags: ["u14", "u16", "u18", "adult", "recovery", "intensity:low", "format:individual", "source:nba"]
        ),
        DrillItem(
            name: "Breath & Body-Scan",
            category: .cooldown, difficulty: .beginner, durationMinutes: 5,
            description: "Five-minute parasympathetic reset — breathwork plus body-scan. Used by NBA performance staff.",
            instructions: [
                "Lie on your back, knees bent",
                "Box breathing: 4-second inhale, 4 hold, 4 exhale, 4 hold — 10 rounds",
                "Body-scan from feet to head"
            ],
            keyPoints: ["Eyes closed", "Breathe through the nose", "Notice tension — don't fix it"],
            equipmentNeeded: [], minPlayers: 1, maxPlayers: 20,
            tags: ["u14", "u16", "u18", "adult", "recovery", "intensity:low", "format:team", "source:nba"]
        ),
    ]

    // MARK: - Team Play / Scrimmage Concepts

    private static let teamPlayElite: [DrillItem] = [
        DrillItem(
            name: "5-out Motion: Pass & Cut",
            category: .offense, difficulty: .intermediate, durationMinutes: 12,
            description: "Five-out motion concept — pass and cut, fill behind. The cleanest motion teach.",
            instructions: [
                "Five players spaced one pass apart around the arc",
                "Pass → cut to the rim → fill the empty wing or corner",
                "Two passes minimum before any shot"
            ],
            keyPoints: ["Cut hard, fill faster", "Sprint to the spot — don't drift", "Keep spacing 15-18 ft between players"],
            equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 5,
            tags: ["u12", "u14", "u16", "u18", "team-play", "passing", "intensity:medium", "format:team", "source:clipboard"]
        ),
        DrillItem(
            name: "Spain PnR Action",
            category: .offense, difficulty: .advanced, durationMinutes: 12,
            description: "Spain pick-and-roll — back-screen on the roller's defender. International staple.",
            instructions: [
                "Ball handler runs PnR with screener",
                "Third player back-screens the screener's defender",
                "Read the chain: pop, lob, or drift to the corner"
            ],
            keyPoints: ["Back-screener stays low and wide", "Ball handler reads the third man's defender", "Spacers stay home until the read finishes"],
            equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 10,
            tags: ["u16", "u18", "adult", "team-play", "game-prep", "intensity:medium", "format:team", "source:fiba"]
        ),
        DrillItem(
            name: "5v5 Half-Court Possessions",
            category: .offense, difficulty: .advanced, durationMinutes: 15,
            description: "Live half-court — score on the first action, swap if you don't.",
            instructions: [
                "Coach calls the action: PnR, ball-screen flare, horns, etc.",
                "Score on the first action — no broken-play resets",
                "Defense gets a stop = takes the ball the other way"
            ],
            keyPoints: ["Talk every screen", "Spacing first, action second", "Defense communicates coverages early"],
            equipmentNeeded: ["Basketball"], minPlayers: 10, maxPlayers: 10,
            tags: ["u14", "u16", "u18", "adult", "team-play", "game-prep", "intensity:high", "format:full-court", "source:nba"]
        ),
        DrillItem(
            name: "Transition Defense Trail",
            category: .defense, difficulty: .intermediate, durationMinutes: 10,
            description: "Defensive transition — load to the paint, point at the ball, then match up.",
            instructions: [
                "Offense scores or misses; defense sprints back",
                "First defender stops the ball; second loads to the paint",
                "Match up by next-closest, not by assignment"
            ],
            keyPoints: ["Sprint back — no jogging on a make", "Communicate matchups loudly", "Take the rim away first"],
            equipmentNeeded: ["Basketball"], minPlayers: 6, maxPlayers: 10,
            tags: ["u12", "u14", "u16", "u18", "adult", "defense", "team-play", "conditioning", "intensity:high", "format:full-court", "source:fiba"]
        ),
        DrillItem(
            name: "BLOB: Stack 14",
            category: .offense, difficulty: .advanced, durationMinutes: 8,
            description: "Baseline-out-of-bounds 'Stack' — high-percentage 3-second action against switching defense.",
            instructions: [
                "Four players stacked on the strong-side block",
                "On slap, top sets a flare for shooter; second sets a back-screen for diver",
                "Inbounder reads — flare three or layup"
            ],
            keyPoints: ["Sell the flare with width", "Diver runs the rim — don't curl", "Inbounder catches the slap, counts 1-1000 before pass"],
            equipmentNeeded: ["Basketball"], minPlayers: 5, maxPlayers: 5,
            tags: ["u14", "u16", "u18", "adult", "team-play", "game-prep", "intensity:medium", "format:team", "source:clipboard"]
        ),
    ]
}
