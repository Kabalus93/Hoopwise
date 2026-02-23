import Foundation

// MARK: - AI Generation Helper Functions
extension FlightyProgramDetailView {
    /// Get difficulty level description based on 1-10 scale
    func difficultyLevelDescription(for level: Int) -> String {
        switch level {
        case 1...2: return "Beginner - Learning basics"
        case 3...4: return "Novice - Building fundamentals"
        case 5...6: return "Intermediate - Developing skills"
        case 7...8: return "Advanced - Competitive level"
        case 9...10: return "Elite - High performance"
        default: return "Intermediate"
        }
    }
    
    /// Get specific training requirements based on difficulty level
    func difficultyRequirements(for level: Int) -> String {
        switch level {
        case 1...2:
            return """
            - Focus on basic motor skills and coordination
            - Simple 1-2 step drills with high repetition
            - Emphasis on fun and engagement
            - Individual skill work before team concepts
            - Short drill durations (3-5 minutes)
            - Positive reinforcement and encouragement
            """
        case 3...4:
            return """
            - Build fundamental techniques with proper form
            - 2-3 step drill progressions
            - Introduction to basic team concepts (passing lanes, spacing)
            - Mix of individual and partner drills
            - Medium drill durations (5-8 minutes)
            - Focus on consistency and repetition
            """
        case 5...6:
            return """
            - Refine techniques and introduce variations
            - Multi-step drill progressions with decision-making
            - Team tactics and positional play
            - Small-sided games (3v3, 4v4)
            - Longer drill durations (8-12 minutes)
            - Introduce competitive elements
            """
        case 7...8:
            return """
            - Advanced techniques and game-specific situations
            - Complex drill progressions with pressure
            - Advanced team systems and strategies
            - Full-court scrimmages with coaching points
            - Extended drill durations (10-15 minutes)
            - High intensity and competitive focus
            """
        case 9...10:
            return """
            - Elite-level techniques and professional concepts
            - Game-speed drills with full defensive pressure
            - Advanced tactical systems and adjustments
            - Film study and strategic analysis
            - Position-specific specialized training
            - Performance metrics and analytics
            """
        default:
            return """
            - Balanced approach to skill development
            - Progressive drill complexity
            - Mix of individual and team concepts
            - Game-based learning activities
            """
        }
    }
}
