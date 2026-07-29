import SwiftUI

// MARK: - Basketball Court Lab View
/// A comprehensive 2D basketball court editor for designing plays and drills
/// Features glass UI elements and movement trail tracking
struct BasketballCourtLabView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @Binding var scheme: CourtScheme
    let onSave: (CourtScheme) -> Void
    
    @State private var currentFrameIndex = 0
    @State private var selectedPlayerId: UUID?
    @State private var selectedMovementId: UUID?  // For selecting movements to edit
    @State private var selectedTool: CourtTool = .select
    @State private var selectedMoveSubTool: MoveSubTool = .run  // Sub-tool for Move
    @State private var selectedDrawSubTool: DrawSubTool = .arrow  // Sub-tool for Draw
    @State private var selectedPathStyle: PathStyle = .sharp
    @State private var isDrawingBallPass = false
    @State private var ballPassStart: CGPoint?
    @State private var showingSettings = false
    
    // Track player movement trails (player positions from previous frame)
    @State private var playerTrails: [UUID: [CGPoint]] = [:]
    
    // Drawing state
    @State private var isDrawing = false
    @State private var drawingStart: CGPoint?
    @State private var drawingPoints: [CGPoint] = []
    
    // Undo history
    @State private var undoStack: [CourtScheme] = []
    
    // Sub-tools for Move tool
    enum MoveSubTool: String, CaseIterable {
        case run, screen
        
        var icon: String {
            switch self {
            case .run: return "figure.run"
            case .screen: return "rectangle.portrait.fill"
            }
        }
        
        var label: String {
            switch self {
            case .run: return "Run"
            case .screen: return "Screen"
            }
        }
    }
    
    // Sub-tools for Draw tool
    enum DrawSubTool: String, CaseIterable {
        case arrow, flat, curved
        
        var icon: String {
            switch self {
            case .arrow: return "arrow.up.right"
            case .flat: return "line.diagonal"
            case .curved: return "scribble"
            }
        }
        
        var label: String {
            switch self {
            case .arrow: return "Arrow"
            case .flat: return "Line"
            case .curved: return "Curve"
            }
        }
        
        var movementType: MovementType {
            switch self {
            case .arrow: return .drawArrow
            case .flat: return .drawFlat
            case .curved: return .drawCurved
            }
        }
    }
    
    enum CourtTool: String, CaseIterable {
        case select, addOffense, addDefense, movement, ball, draw, eraser
        
        var icon: String {
            switch self {
            case .select: return "hand.point.up.left"
            case .addOffense: return "circle"
            case .addDefense: return "circle.fill"
            case .movement: return "arrow.right"
            case .ball: return "basketball"
            case .draw: return "pencil.tip"
            case .eraser: return "eraser"
            }
        }
        
        var label: String {
            switch self {
            case .select: return "Select"
            case .addOffense: return "Offense"
            case .addDefense: return "Defense"
            case .movement: return "Move"
            case .ball: return "Ball"
            case .draw: return "Draw"
            case .eraser: return "Erase"
            }
        }
        
        var color: Color {
            switch self {
            case .select: return .blue
            case .addOffense: return .white
            case .addDefense: return .yellow
            case .movement: return .cyan
            case .ball: return .orange
            case .draw: return .purple
            case .eraser: return .red
            }
        }
    }
    
    var currentFrame: CourtFrame {
        guard currentFrameIndex < scheme.frames.count else {
            return CourtFrame(order: 0)
        }
        return scheme.frames[currentFrameIndex]
    }
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Glass Header
                glassHeader
                
                HStack(spacing: 0) {
                    // Left Glass Toolbar
                    glassToolbar
                        .frame(width: 70)
                    
                    // Main court area
                    GeometryReader { geometry in
                        ZStack {
                            BasketballCourtView(
                                frame: currentFrame,
                                selectedPlayerId: $selectedPlayerId,
                                selectedMovementId: $selectedMovementId,
                                selectedTool: selectedTool,
                                playerTrails: playerTrails,
                                isDrawingBallPass: isDrawingBallPass,
                                ballPassStart: ballPassStart,
                                isDrawing: isDrawing,
                                drawingPoints: drawingPoints,
                                selectedDrawSubTool: selectedDrawSubTool,
                                onTapCourt: handleCourtTap,
                                onDragPlayer: handlePlayerDrag,
                                onDragEnd: handlePlayerDragEnd,
                                onTapPlayer: handlePlayerTap,
                                onTapMovement: handleMovementTap,
                                onAddWaypoint: handleMovementWaypointAdd,
                                onDrawStart: handleDrawStart,
                                onDrawUpdate: handleDrawUpdate,
                                onDrawEnd: handleDrawEnd
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(16)
                    
                    // Right Glass Properties Panel
                    glassPropertiesPanel
                        .frame(width: 260)
                }
                
                // Glass Frame Timeline
                glassFrameTimeline
            }
        }
    }
    
    // MARK: - Glass Header
    private var glassHeader: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Scheme name with glass pill
            HStack(spacing: 8) {
                Image(systemName: scheme.schemeType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("Scheme Name", text: $scheme.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.4))
            .clipShape(Capsule())
            
            Spacer()
            
            // Type picker
            Menu {
                ForEach(SchemeType.allCases, id: \.self) { type in
                    Button(action: { scheme.schemeType = type }) {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: scheme.schemeType.icon)
                    Text(scheme.schemeType.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.4))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Undo button
            Button(action: performUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(undoStack.isEmpty ? .white.opacity(0.3) : .white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(undoStack.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
            
            // Save button
            Button(action: saveScheme) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.3))
    }
    
    // MARK: - Glass Toolbar
    private var glassToolbar: some View {
        VStack(spacing: 8) {
            // Tool buttons
            ForEach(CourtTool.allCases, id: \.self) { tool in
                GlassToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    color: tool.color,
                    isSelected: selectedTool == tool
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTool = tool
                        selectedMovementId = nil
                    }
                }
            }
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            // Move tool sub-options
            if selectedTool == .movement {
                VStack(spacing: 6) {
                    Text("TYPE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    ForEach(MoveSubTool.allCases, id: \.self) { subTool in
                        Button(action: { selectedMoveSubTool = subTool }) {
                            VStack(spacing: 2) {
                                Image(systemName: subTool.icon)
                                    .font(.system(size: 14))
                                Text(subTool.label)
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(selectedMoveSubTool == subTool ? .cyan : .white.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .background(selectedMoveSubTool == subTool ? .cyan.opacity(0.2) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Draw tool sub-options
            if selectedTool == .draw {
                VStack(spacing: 6) {
                    Text("STYLE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    ForEach(DrawSubTool.allCases, id: \.self) { subTool in
                        Button(action: { selectedDrawSubTool = subTool }) {
                            VStack(spacing: 2) {
                                Image(systemName: subTool.icon)
                                    .font(.system(size: 14))
                                Text(subTool.label)
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(selectedDrawSubTool == subTool ? .purple : .white.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .background(selectedDrawSubTool == subTool ? .purple.opacity(0.2) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Select tool - path style options when movement is selected
            if selectedTool == .select && selectedMovementId != nil {
                VStack(spacing: 6) {
                    Text("PATH")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    ForEach(PathStyle.allCases, id: \.self) { style in
                        Button(action: { 
                            selectedPathStyle = style
                            updateMovementPathStyle(style)
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: style == .sharp ? "line.diagonal" : "scribble")
                                    .font(.system(size: 14))
                                Text(style.displayName)
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(selectedPathStyle == style ? .purple : .white.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .background(selectedPathStyle == style ? .purple.opacity(0.2) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Delete movement button
                    Button(action: { deleteSelectedMovement() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                            Text("Delete")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Player count indicators
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                    Text("\(currentFrame.players.filter { $0.team == .offense }.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                    Text("\(currentFrame.players.filter { $0.team == .defense }.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial.opacity(0.3))
    }
    
    // MARK: - Glass Properties Panel
    private var glassPropertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Selected player properties
            if let playerId = selectedPlayerId,
               let playerIndex = currentFrame.players.firstIndex(where: { $0.id == playerId }) {
                let player = currentFrame.players[playerIndex]
                
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Circle()
                            .fill(player.team == .offense ? Color.white : Color.yellow)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(player.number.map { "\($0)" } ?? "")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                            )
                        
                        Text(player.team == .offense ? "Offensive Player" : "Defensive Player")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    // Team toggle
                    GlassPropertyRow(label: "Team") {
                        HStack(spacing: 8) {
                            GlassToggleChip(
                                label: "O",
                                color: .white,
                                isSelected: player.team == .offense
                            ) {
                                updatePlayer(playerId) { $0.team = .offense }
                            }
                            GlassToggleChip(
                                label: "D",
                                color: .yellow,
                                isSelected: player.team == .defense
                            ) {
                                updatePlayer(playerId) { $0.team = .defense }
                            }
                        }
                    }
                    
                    // Number
                    GlassPropertyRow(label: "Number") {
                        HStack(spacing: 4) {
                            ForEach([1, 2, 3, 4, 5], id: \.self) { num in
                                GlassNumberChip(
                                    number: num,
                                    isSelected: player.number == num
                                ) {
                                    updatePlayer(playerId) { $0.number = num }
                                }
                            }
                        }
                    }
                    
                    // Has ball toggle
                    GlassPropertyRow(label: "Has Ball") {
                        Toggle("", isOn: Binding(
                            get: { player.hasBall },
                            set: { newValue in
                                if newValue {
                                    // Clear ball from others
                                    for i in 0..<scheme.frames[currentFrameIndex].players.count {
                                        scheme.frames[currentFrameIndex].players[i].hasBall = false
                                    }
                                }
                                updatePlayer(playerId) { $0.hasBall = newValue }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                    
                    // Delete button
                    Button(action: { deletePlayer(playerId) }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove Player")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(.ultraThinMaterial.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(12)
            } else {
                // No selection hint
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Select a player\nor tap court to add")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 12)
            }
            
            Spacer()
            
            // Frame info
            VStack(alignment: .leading, spacing: 8) {
                Text("FRAME INFO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                GlassInfoRow(label: "Players", value: "\(currentFrame.players.count)")
                GlassInfoRow(label: "Movements", value: "\(currentFrame.movements.count)")
                GlassInfoRow(label: "Frame", value: "\(currentFrameIndex + 1) of \(scheme.frames.count)")
            }
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(12)
        }
        .background(.ultraThinMaterial.opacity(0.2))
    }
    
    // MARK: - Glass Frame Timeline
    private var glassFrameTimeline: some View {
        HStack(spacing: 12) {
            // Previous frame
            GlassIconButton(icon: "chevron.left", size: 28) {
                if currentFrameIndex > 0 {
                    withAnimation { currentFrameIndex -= 1 }
                    updateTrails()
                }
            }
            .disabled(currentFrameIndex == 0)
            .opacity(currentFrameIndex == 0 ? 0.3 : 1)
            
            // Frame thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(scheme.frames.enumerated()), id: \.element.id) { index, frame in
                        GlassFrameThumbnail(
                            frame: frame,
                            index: index,
                            isSelected: currentFrameIndex == index
                        ) {
                            withAnimation { currentFrameIndex = index }
                            updateTrails()
                        }
                    }
                    
                    // Add frame button
                    Button(action: addFrame) {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(width: 70, height: 46)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                            Text("Add")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }
            
            // Next frame
            GlassIconButton(icon: "chevron.right", size: 28) {
                if currentFrameIndex < scheme.frames.count - 1 {
                    withAnimation { currentFrameIndex += 1 }
                    updateTrails()
                }
            }
            .disabled(currentFrameIndex >= scheme.frames.count - 1)
            .opacity(currentFrameIndex >= scheme.frames.count - 1 ? 0.3 : 1)
            
            // Separator
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 30)
            
            // Frame actions
            GlassIconButton(icon: "doc.on.doc", size: 28) {
                duplicateCurrentFrame()
            }
            
            GlassIconButton(icon: "trash", size: 28, color: .red) {
                deleteCurrentFrame()
            }
            .disabled(scheme.frames.count <= 1)
            .opacity(scheme.frames.count <= 1 ? 0.3 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.3))
    }
    
    // MARK: - Actions
    private func handleCourtTap(at normalizedPoint: CGPoint) {
        switch selectedTool {
        case .addOffense:
            addPlayer(at: normalizedPoint, team: .offense)
        case .addDefense:
            addPlayer(at: normalizedPoint, team: .defense)
        case .select:
            selectedPlayerId = nil
            selectedMovementId = nil
        case .ball:
            // Ball tool - tap on court to set ball pass destination
            if isDrawingBallPass, let start = ballPassStart {
                // Complete the ball pass
                saveStateForUndo()
                let movement = CourtMovement(
                    startPoint: start,
                    endPoint: normalizedPoint,
                    movementType: .pass,
                    playerId: nil
                )
                scheme.frames[currentFrameIndex].movements.append(movement)
                isDrawingBallPass = false
                ballPassStart = nil
            }
        default:
            break
        }
    }
    
    private func handlePlayerTap(_ playerId: UUID) {
        if selectedTool == .eraser {
            deletePlayer(playerId)
        } else if selectedTool == .ball {
            // Ball tool - start ball pass from this player
            if let player = currentFrame.players.first(where: { $0.id == playerId }) {
                if isDrawingBallPass {
                    // Complete pass to this player
                    if let start = ballPassStart {
                        saveStateForUndo()
                        let movement = CourtMovement(
                            startPoint: start,
                            endPoint: player.position,
                            movementType: .pass,
                            playerId: nil
                        )
                        scheme.frames[currentFrameIndex].movements.append(movement)
                        
                        // Transfer ball
                        for i in 0..<scheme.frames[currentFrameIndex].players.count {
                            scheme.frames[currentFrameIndex].players[i].hasBall = false
                        }
                        updatePlayer(playerId) { $0.hasBall = true }
                    }
                    isDrawingBallPass = false
                    ballPassStart = nil
                } else {
                    // Start pass from this player (must have ball)
                    if player.hasBall {
                        isDrawingBallPass = true
                        ballPassStart = player.position
                    }
                }
            }
        } else {
            selectedPlayerId = playerId
            selectedMovementId = nil
        }
    }
    
    private func handleMovementTap(_ movementId: UUID) {
        if selectedTool == .select {
            selectedMovementId = movementId
            selectedPlayerId = nil
            // Load current path style
            if let movement = currentFrame.movements.first(where: { $0.id == movementId }) {
                selectedPathStyle = movement.pathStyle
            }
        } else if selectedTool == .eraser {
            scheme.frames[currentFrameIndex].movements.removeAll { $0.id == movementId }
        }
    }
    
    private func handleMovementWaypointAdd(_ movementId: UUID, at point: CGPoint) {
        // Add waypoint to movement for bending
        if let index = scheme.frames[currentFrameIndex].movements.firstIndex(where: { $0.id == movementId }) {
            scheme.frames[currentFrameIndex].movements[index].waypoints.append(point)
        }
    }
    
    private func handlePlayerDrag(_ playerId: UUID, to newPosition: CGPoint) {
        // Only record trails when Move tool is selected (not Ball tool)
        if selectedTool == .movement {
            if playerTrails[playerId] == nil {
                // Start trail from current position
                if let player = currentFrame.players.first(where: { $0.id == playerId }) {
                    playerTrails[playerId] = [player.position]
                }
            }
            playerTrails[playerId]?.append(newPosition)
        }
        
        // Always update player position (Select and Move tools)
        if selectedTool == .select || selectedTool == .movement {
            updatePlayer(playerId) { $0.position = newPosition }
        }
    }
    
    private func handlePlayerDragEnd(_ playerId: UUID) {
        // Only create movement when Move tool is selected
        guard selectedTool == .movement else {
            playerTrails[playerId] = nil
            return
        }
        
        // Convert trail to movement
        guard let trail = playerTrails[playerId], trail.count >= 2 else {
            playerTrails[playerId] = nil
            return
        }
        
        let startPoint = trail.first!
        let endPoint = trail.last!
        
        // Determine movement type based on sub-tool
        // Player with ball uses .run (continuous line), not .dribble
        // Ball movement (pass) is handled separately by Ball tool
        let movementType: MovementType
        if selectedMoveSubTool == .screen {
            movementType = .screen
        } else {
            movementType = .run  // Always continuous line for player movement
        }
        
        // Add movement to frame
        saveStateForUndo()
        let movement = CourtMovement(
            startPoint: startPoint,
            endPoint: endPoint,
            movementType: movementType,
            pathStyle: selectedPathStyle,
            playerId: playerId
        )
        scheme.frames[currentFrameIndex].movements.append(movement)
        
        // Clear trail
        playerTrails[playerId] = nil
    }
    
    private func updateMovementPathStyle(_ style: PathStyle) {
        guard let movementId = selectedMovementId else { return }
        if let index = scheme.frames[currentFrameIndex].movements.firstIndex(where: { $0.id == movementId }) {
            scheme.frames[currentFrameIndex].movements[index].pathStyle = style
        }
    }
    
    // MARK: - Draw Tool Handlers
    private func handleDrawStart(at point: CGPoint) {
        guard selectedTool == .draw else { return }
        isDrawing = true
        drawingStart = point
        drawingPoints = [point]
    }
    
    private func handleDrawUpdate(to point: CGPoint) {
        guard isDrawing else { return }
        drawingPoints.append(point)
    }
    
    private func handleDrawEnd() {
        guard isDrawing, drawingPoints.count >= 2 else {
            isDrawing = false
            drawingPoints = []
            drawingStart = nil
            return
        }
        
        saveStateForUndo()
        
        let startPoint = drawingPoints.first!
        let endPoint = drawingPoints.last!
        
        // For curved lines, keep intermediate points as waypoints
        var waypoints: [CGPoint] = []
        if selectedDrawSubTool == .curved && drawingPoints.count > 2 {
            // Sample some intermediate points for the curve
            let step = max(1, drawingPoints.count / 5)
            for i in stride(from: step, to: drawingPoints.count - 1, by: step) {
                waypoints.append(drawingPoints[i])
            }
        }
        
        let movement = CourtMovement(
            startPoint: startPoint,
            endPoint: endPoint,
            waypoints: waypoints,
            movementType: selectedDrawSubTool.movementType,
            pathStyle: selectedDrawSubTool == .curved ? .curved : .sharp,
            playerId: nil
        )
        scheme.frames[currentFrameIndex].movements.append(movement)
        
        // Reset drawing state
        isDrawing = false
        drawingPoints = []
        drawingStart = nil
    }
    
    private func deleteSelectedMovement() {
        guard let movementId = selectedMovementId else { return }
        saveStateForUndo()
        scheme.frames[currentFrameIndex].movements.removeAll { $0.id == movementId }
        selectedMovementId = nil
    }
    
    private func addPlayer(at position: CGPoint, team: CourtTeam) {
        saveStateForUndo()
        let teamPlayers = currentFrame.players.filter { $0.team == team }
        let nextNumber = (teamPlayers.compactMap { $0.number }.max() ?? 0) + 1
        
        let newPlayer = CourtPlayer(
            position: position,
            team: team,
            number: min(nextNumber, 5),
            hasBall: team == .offense && currentFrame.players.filter { $0.hasBall }.isEmpty
        )
        scheme.frames[currentFrameIndex].players.append(newPlayer)
        selectedPlayerId = newPlayer.id
    }
    
    private func updatePlayer(_ playerId: UUID, update: (inout CourtPlayer) -> Void) {
        if let index = scheme.frames[currentFrameIndex].players.firstIndex(where: { $0.id == playerId }) {
            update(&scheme.frames[currentFrameIndex].players[index])
        }
    }
    
    private func deletePlayer(_ playerId: UUID) {
        saveStateForUndo()
        scheme.frames[currentFrameIndex].players.removeAll { $0.id == playerId }
        scheme.frames[currentFrameIndex].movements.removeAll { $0.playerId == playerId }
        playerTrails.removeValue(forKey: playerId)
        if selectedPlayerId == playerId {
            selectedPlayerId = nil
        }
    }
    
    private func addFrame() {
        saveStateForUndo()
        let newFrame = CourtFrame(
            players: currentFrame.players.map { player in
                CourtPlayer(position: player.position, team: player.team, number: player.number, label: player.label, hasBall: player.hasBall)
            },
            movements: [],
            order: scheme.frames.count
        )
        scheme.frames.append(newFrame)
        currentFrameIndex = scheme.frames.count - 1
        playerTrails.removeAll()
    }
    
    private func deleteCurrentFrame() {
        guard scheme.frames.count > 1 else { return }
        saveStateForUndo()
        scheme.frames.remove(at: currentFrameIndex)
        if currentFrameIndex >= scheme.frames.count {
            currentFrameIndex = scheme.frames.count - 1
        }
        playerTrails.removeAll()
    }
    
    private func duplicateCurrentFrame() {
        saveStateForUndo()
        let newFrame = CourtFrame(
            id: UUID(),
            players: currentFrame.players.map { player in
                CourtPlayer(position: player.position, team: player.team, number: player.number, label: player.label, hasBall: player.hasBall)
            },
            movements: currentFrame.movements,
            order: scheme.frames.count
        )
        scheme.frames.insert(newFrame, at: currentFrameIndex + 1)
        currentFrameIndex += 1
        playerTrails.removeAll()
    }
    
    private func updateTrails() {
        playerTrails.removeAll()
    }
    
    private func saveStateForUndo() {
        // Save current state before making changes
        undoStack.append(scheme)
        // Limit undo stack size to prevent memory issues
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    private func performUndo() {
        guard let previousState = undoStack.popLast() else { return }
        scheme = previousState
        selectedPlayerId = nil
        selectedMovementId = nil
        playerTrails.removeAll()
    }
    
    private func saveScheme() {
        scheme.updatedAt = Date()
        onSave(scheme)
        dismiss()
    }
}

// MARK: - Glass UI Components

struct GlassToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color.opacity(0.3))
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? color : .white.opacity(0.6))
                }
                .frame(width: 44, height: 44)
                
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(isSelected ? color : .white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

struct GlassMovementTypeButton: View {
    let type: MovementType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: type.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .cyan : .white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(isSelected ? .cyan.opacity(0.2) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct GlassIconButton: View {
    let icon: String
    let size: CGFloat
    var color: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(color.opacity(0.8))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial.opacity(0.4))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GlassPropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            content
        }
    }
}

struct GlassToggleChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(isSelected ? color : .white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GlassNumberChip: View {
    let number: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(isSelected ? .white : .white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GlassInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct GlassFrameThumbnail: View {
    let frame: CourtFrame
    let index: Int
    let isSelected: Bool
    let action: () -> Void
    
    // Thumbnail dimensions
    private let thumbWidth: CGFloat = 70
    private let thumbHeight: CGFloat = 46
    private let courtWidth: CGFloat = 64
    private let courtHeight: CGFloat = 40
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Use Canvas for precise coordinate control
                Canvas { context, size in
                    // Court background
                    let bgRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                    context.fill(RoundedRectangle(cornerRadius: 6).path(in: bgRect), with: .color(.black))
                    
                    // Court outline - centered
                    let courtX = (size.width - courtWidth) / 2
                    let courtY = (size.height - courtHeight) / 2
                    let courtRect = CGRect(x: courtX, y: courtY, width: courtWidth, height: courtHeight)
                    context.stroke(
                        RoundedRectangle(cornerRadius: 4).path(in: courtRect),
                        with: .color(.white.opacity(0.3)),
                        lineWidth: 0.5
                    )
                    
                    // Half court line
                    var halfLine = Path()
                    halfLine.move(to: CGPoint(x: size.width / 2, y: courtY))
                    halfLine.addLine(to: CGPoint(x: size.width / 2, y: courtY + courtHeight))
                    context.stroke(halfLine, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                    
                    // Players - positioned relative to court bounds
                    for player in frame.players {
                        let playerX = courtX + player.position.x * courtWidth
                        let playerY = courtY + player.position.y * courtHeight
                        let playerRect = CGRect(x: playerX - 2.5, y: playerY - 2.5, width: 5, height: 5)
                        context.fill(
                            Circle().path(in: playerRect),
                            with: .color(player.team == .offense ? .white : .yellow)
                        )
                    }
                    
                    // Movements as lines
                    for movement in frame.movements {
                        var movePath = Path()
                        movePath.move(to: CGPoint(
                            x: courtX + movement.startPoint.x * courtWidth,
                            y: courtY + movement.startPoint.y * courtHeight
                        ))
                        movePath.addLine(to: CGPoint(
                            x: courtX + movement.endPoint.x * courtWidth,
                            y: courtY + movement.endPoint.y * courtHeight
                        ))
                        context.stroke(movePath, with: .color(.cyan.opacity(0.6)), lineWidth: 1)
                    }
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Basketball Court View (2D Rendering)
struct BasketballCourtView: View {
    let frame: CourtFrame
    @Binding var selectedPlayerId: UUID?
    @Binding var selectedMovementId: UUID?
    let selectedTool: BasketballCourtLabView.CourtTool
    let playerTrails: [UUID: [CGPoint]]
    let isDrawingBallPass: Bool
    let ballPassStart: CGPoint?
    let isDrawing: Bool
    let drawingPoints: [CGPoint]
    let selectedDrawSubTool: BasketballCourtLabView.DrawSubTool
    let onTapCourt: (CGPoint) -> Void
    let onDragPlayer: (UUID, CGPoint) -> Void
    let onDragEnd: (UUID) -> Void
    let onTapPlayer: (UUID) -> Void
    let onTapMovement: (UUID) -> Void
    let onAddWaypoint: (UUID, CGPoint) -> Void
    let onDrawStart: (CGPoint) -> Void
    let onDrawUpdate: (CGPoint) -> Void
    let onDrawEnd: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let courtSize = calculateCourtSize(in: geometry.size)
            let courtOrigin = CGPoint(
                x: (geometry.size.width - courtSize.width) / 2,
                y: (geometry.size.height - courtSize.height) / 2
            )
            
            ZStack {
                // Court background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .frame(width: courtSize.width + 20, height: courtSize.height + 20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Court lines
                CourtLinesView()
                    .frame(width: courtSize.width, height: courtSize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Movement lines (from frame data) - tappable for selection
                ForEach(frame.movements) { movement in
                    MovementLineView(
                        movement: movement,
                        isSelected: selectedMovementId == movement.id,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin
                    )
                    .onTapGesture {
                        onTapMovement(movement.id)
                    }
                }
                
                // Ball pass preview line
                if isDrawingBallPass, let start = ballPassStart {
                    BallPassPreviewLine(
                        startPoint: start,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin
                    )
                }
                
                // Active drag trails (always continuous for player movement)
                ForEach(Array(playerTrails.keys), id: \.self) { playerId in
                    if let trail = playerTrails[playerId], trail.count >= 2 {
                        TrailLineView(
                            points: trail,
                            courtSize: courtSize,
                            courtOrigin: courtOrigin,
                            isDashed: false  // Player movement is always continuous
                        )
                    }
                }
                
                // Drawing preview
                if isDrawing && drawingPoints.count >= 2 {
                    DrawingPreviewLine(
                        points: drawingPoints,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin,
                        drawSubTool: selectedDrawSubTool
                    )
                }
                
                // Players
                ForEach(frame.players) { player in
                    PlayerMarkerView(
                        player: player,
                        isSelected: selectedPlayerId == player.id,
                        courtSize: courtSize,
                        courtOrigin: courtOrigin
                    )
                    .onTapGesture {
                        onTapPlayer(player.id)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newX = (value.location.x - courtOrigin.x) / courtSize.width
                                let newY = (value.location.y - courtOrigin.y) / courtSize.height
                                let clampedPoint = CGPoint(
                                    x: max(0, min(1, newX)),
                                    y: max(0, min(1, newY))
                                )
                                onDragPlayer(player.id, clampedPoint)
                            }
                            .onEnded { _ in
                                onDragEnd(player.id)
                            }
                    )
                }
                
                // Tool cursor indicator
                if selectedTool == .addOffense || selectedTool == .addDefense {
                    ToolCursorOverlay(tool: selectedTool)
                }
                
                // Ball tool indicator
                if selectedTool == .ball {
                    BallToolOverlay(isDrawing: isDrawingBallPass)
                }
                
                // Draw tool indicator
                if selectedTool == .draw {
                    DrawToolOverlay()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalizedX = (location.x - courtOrigin.x) / courtSize.width
                let normalizedY = (location.y - courtOrigin.y) / courtSize.height
                if normalizedX >= 0 && normalizedX <= 1 && normalizedY >= 0 && normalizedY <= 1 {
                    onTapCourt(CGPoint(x: normalizedX, y: normalizedY))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard selectedTool == .draw else { return }
                        let normalizedX = (value.location.x - courtOrigin.x) / courtSize.width
                        let normalizedY = (value.location.y - courtOrigin.y) / courtSize.height
                        let clampedPoint = CGPoint(
                            x: max(0, min(1, normalizedX)),
                            y: max(0, min(1, normalizedY))
                        )
                        if value.translation == .zero || drawingPoints.isEmpty {
                            onDrawStart(clampedPoint)
                        } else {
                            onDrawUpdate(clampedPoint)
                        }
                    }
                    .onEnded { _ in
                        guard selectedTool == .draw else { return }
                        onDrawEnd()
                    }
            )
        }
    }
    
    private func calculateCourtSize(in containerSize: CGSize) -> CGSize {
        let courtAspectRatio: CGFloat = 94.0 / 50.0
        let containerAspectRatio = containerSize.width / containerSize.height
        
        if containerAspectRatio > courtAspectRatio {
            let height = containerSize.height * 0.9
            return CGSize(width: height * courtAspectRatio, height: height)
        } else {
            let width = containerSize.width * 0.9
            return CGSize(width: width, height: width / courtAspectRatio)
        }
    }
}

// MARK: - Tool Cursor Overlay
struct ToolCursorOverlay: View {
    let tool: BasketballCourtLabView.CourtTool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(tool == .addOffense ? Color.white : Color.yellow)
                        .frame(width: 12, height: 12)
                    Text("Tap to add \(tool == .addOffense ? "offensive" : "defensive") player")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(Capsule())
                .padding(16)
            }
        }
    }
}

// MARK: - Trail Line View
struct TrailLineView: View {
    let points: [CGPoint]
    let courtSize: CGSize
    let courtOrigin: CGPoint
    let isDashed: Bool
    
    var body: some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(
                x: courtOrigin.x + first.x * courtSize.width,
                y: courtOrigin.y + first.y * courtSize.height
            ))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: courtOrigin.x + point.x * courtSize.width,
                    y: courtOrigin.y + point.y * courtSize.height
                ))
            }
        }
        .stroke(
            isDashed ? Color.orange : Color.cyan,
            style: isDashed ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 2)
        )
    }
}

// MARK: - Movement Line View
struct MovementLineView: View {
    let movement: CourtMovement
    let isSelected: Bool
    let courtSize: CGSize
    let courtOrigin: CGPoint
    
    var body: some View {
        let endX = courtOrigin.x + movement.endPoint.x * courtSize.width
        let endY = courtOrigin.y + movement.endPoint.y * courtSize.height
        
        // Build path with waypoints
        let allPoints = [movement.startPoint] + movement.waypoints + [movement.endPoint]
        
        ZStack {
            // Selection highlight
            if isSelected {
                buildPath(points: allPoints)
                    .stroke(Color.purple.opacity(0.4), lineWidth: 8)
            }
            
            // Main line (curved or sharp based on pathStyle)
            if movement.pathStyle == .curved && allPoints.count > 2 {
                buildCurvedPath(points: allPoints)
                    .stroke(movementColor, style: strokeStyle)
            } else {
                buildPath(points: allPoints)
                    .stroke(movementColor, style: strokeStyle)
            }
            
            // Arrow head at end (for most types except flat line)
            if movement.movementType != .drawFlat {
                ArrowHead(start: secondToLastPoint(allPoints), end: CGPoint(x: endX, y: endY))
                    .fill(movementColor)
            }
            
            // Flat end marker for drawFlat type
            if movement.movementType == .drawFlat {
                FlatEndMarker(
                    start: secondToLastPoint(allPoints),
                    end: CGPoint(x: endX, y: endY)
                )
                .stroke(movementColor, lineWidth: 2)
            }
            
            // Screen perpendicular line at end
            if movement.movementType == .screen {
                ScreenEndMarker(
                    start: secondToLastPoint(allPoints),
                    end: CGPoint(x: endX, y: endY)
                )
                .stroke(movementColor, lineWidth: 3)
            }
            
            // Waypoint handles when selected
            if isSelected {
                ForEach(Array(movement.waypoints.enumerated()), id: \.offset) { index, waypoint in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 10, height: 10)
                        .position(
                            x: courtOrigin.x + waypoint.x * courtSize.width,
                            y: courtOrigin.y + waypoint.y * courtSize.height
                        )
                }
            }
        }
        .contentShape(
            buildPath(points: allPoints)
                .strokedPath(StrokeStyle(lineWidth: 12))
        )
    }
    
    private func buildPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(
                x: courtOrigin.x + first.x * courtSize.width,
                y: courtOrigin.y + first.y * courtSize.height
            ))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: courtOrigin.x + point.x * courtSize.width,
                    y: courtOrigin.y + point.y * courtSize.height
                ))
            }
        }
    }
    
    private func buildCurvedPath(points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else { return }
            let screenPoints = points.map { CGPoint(
                x: courtOrigin.x + $0.x * courtSize.width,
                y: courtOrigin.y + $0.y * courtSize.height
            )}
            
            path.move(to: screenPoints[0])
            
            if screenPoints.count == 2 {
                path.addLine(to: screenPoints[1])
            } else {
                for i in 1..<screenPoints.count {
                    let current = screenPoints[i]
                    let previous = screenPoints[i - 1]
                    let control = CGPoint(
                        x: (previous.x + current.x) / 2,
                        y: (previous.y + current.y) / 2
                    )
                    if i == 1 {
                        path.addLine(to: control)
                    }
                    path.addQuadCurve(to: current, control: control)
                }
            }
        }
    }
    
    private func secondToLastPoint(_ points: [CGPoint]) -> CGPoint {
        let screenPoints = points.map { CGPoint(
            x: courtOrigin.x + $0.x * courtSize.width,
            y: courtOrigin.y + $0.y * courtSize.height
        )}
        if screenPoints.count >= 2 {
            return screenPoints[screenPoints.count - 2]
        }
        return screenPoints.first ?? .zero
    }
    
    var movementColor: Color {
        switch movement.movementType {
        case .run: return .cyan
        case .dribble: return .orange
        case .pass: return .green
        case .screen: return .yellow
        case .cut: return .purple
        case .drawArrow, .drawFlat, .drawCurved: return .purple
        }
    }
    
    var strokeStyle: StrokeStyle {
        switch movement.movementType {
        case .run: return StrokeStyle(lineWidth: 2)
        case .dribble: return StrokeStyle(lineWidth: 2, dash: [6, 4])
        case .pass: return StrokeStyle(lineWidth: 2, dash: [3, 3])
        case .screen: return StrokeStyle(lineWidth: 3)
        case .cut: return StrokeStyle(lineWidth: 2, dash: [2, 2])
        case .drawArrow, .drawFlat, .drawCurved: return StrokeStyle(lineWidth: 2)
        }
    }
}

// MARK: - Screen End Marker (perpendicular line)
struct ScreenEndMarker: Shape {
    let start: CGPoint
    let end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate perpendicular direction
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return path }
        
        // Perpendicular unit vector
        let perpX = -dy / length
        let perpY = dx / length
        
        // Draw perpendicular line at end point
        let lineLength: CGFloat = 12
        path.move(to: CGPoint(
            x: end.x + perpX * lineLength,
            y: end.y + perpY * lineLength
        ))
        path.addLine(to: CGPoint(
            x: end.x - perpX * lineLength,
            y: end.y - perpY * lineLength
        ))
        
        return path
    }
}

// MARK: - Ball Pass Preview Line
struct BallPassPreviewLine: View {
    let startPoint: CGPoint
    let courtSize: CGSize
    let courtOrigin: CGPoint
    
    var body: some View {
        let startX = courtOrigin.x + startPoint.x * courtSize.width
        let startY = courtOrigin.y + startPoint.y * courtSize.height
        
        Circle()
            .stroke(Color.green.opacity(0.6), lineWidth: 2)
            .frame(width: 20, height: 20)
            .position(x: startX, y: startY)
    }
}

// MARK: - Ball Tool Overlay
struct BallToolOverlay: View {
    let isDrawing: Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "basketball")
                        .foregroundColor(.orange)
                    Text(isDrawing ? "Tap player to pass to" : "Tap player with ball to start pass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(Capsule())
                .padding(16)
            }
        }
    }
}

// MARK: - Draw Tool Overlay
struct DrawToolOverlay: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip")
                        .foregroundColor(.purple)
                    Text("Drag to draw on court")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(Capsule())
                .padding(16)
            }
        }
    }
}

// MARK: - Drawing Preview Line
struct DrawingPreviewLine: View {
    let points: [CGPoint]
    let courtSize: CGSize
    let courtOrigin: CGPoint
    let drawSubTool: BasketballCourtLabView.DrawSubTool
    
    var body: some View {
        let screenPoints = points.map { CGPoint(
            x: courtOrigin.x + $0.x * courtSize.width,
            y: courtOrigin.y + $0.y * courtSize.height
        )}
        
        ZStack {
            // Main line
            if drawSubTool == .curved {
                // Smooth curved line
                Path { path in
                    guard screenPoints.count >= 2 else { return }
                    path.move(to: screenPoints[0])
                    
                    if screenPoints.count == 2 {
                        path.addLine(to: screenPoints[1])
                    } else {
                        for i in 1..<screenPoints.count {
                            let current = screenPoints[i]
                            let previous = screenPoints[i - 1]
                            let control = CGPoint(
                                x: (previous.x + current.x) / 2,
                                y: (previous.y + current.y) / 2
                            )
                            if i == 1 {
                                path.addLine(to: control)
                            }
                            path.addQuadCurve(to: current, control: control)
                        }
                    }
                }
                .stroke(Color.purple, lineWidth: 2)
            } else {
                // Straight line from start to end
                Path { path in
                    guard let first = screenPoints.first, let last = screenPoints.last else { return }
                    path.move(to: first)
                    path.addLine(to: last)
                }
                .stroke(Color.purple, lineWidth: 2)
            }
            
            // Arrow head for arrow type
            if drawSubTool == .arrow, let first = screenPoints.first, let last = screenPoints.last {
                ArrowHead(start: first, end: last)
                    .fill(Color.purple)
            }
            
            // Flat end marker for flat type
            if drawSubTool == .flat, screenPoints.count >= 2 {
                let first = screenPoints.first!
                let last = screenPoints.last!
                FlatEndMarker(start: first, end: last)
                    .stroke(Color.purple, lineWidth: 2)
            }
        }
    }
}

// MARK: - Flat End Marker (perpendicular line at end, no arrow)
struct FlatEndMarker: Shape {
    let start: CGPoint
    let end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return path }
        
        let perpX = -dy / length
        let perpY = dx / length
        
        let lineLength: CGFloat = 8
        path.move(to: CGPoint(
            x: end.x + perpX * lineLength,
            y: end.y + perpY * lineLength
        ))
        path.addLine(to: CGPoint(
            x: end.x - perpX * lineLength,
            y: end.y - perpY * lineLength
        ))
        
        return path
    }
}

// MARK: - Court Lines View (Horizontal Full Court)
struct CourtLinesView: View {
    let lineColor = Color.white.opacity(0.6)
    let lineWidth: CGFloat = 1.5
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let courtWidth = size.width
                let courtHeight = size.height
                let scaleX = courtWidth / 94.0
                let scaleY = courtHeight / 50.0
                
                // Court outline
                let courtRect = CGRect(x: 0, y: 0, width: courtWidth, height: courtHeight)
                context.stroke(Path(courtRect), with: .color(lineColor), lineWidth: lineWidth)
                
                // Half court line
                var halfCourtPath = Path()
                halfCourtPath.move(to: CGPoint(x: courtWidth / 2, y: 0))
                halfCourtPath.addLine(to: CGPoint(x: courtWidth / 2, y: courtHeight))
                context.stroke(halfCourtPath, with: .color(lineColor), lineWidth: lineWidth)
                
                // Center circle
                let centerCircleRadius = 6.0 * min(scaleX, scaleY)
                let centerCircle = Path(ellipseIn: CGRect(
                    x: courtWidth / 2 - centerCircleRadius,
                    y: courtHeight / 2 - centerCircleRadius,
                    width: centerCircleRadius * 2,
                    height: centerCircleRadius * 2
                ))
                context.stroke(centerCircle, with: .color(lineColor), lineWidth: lineWidth)
                
                // Both halves
                drawHalfCourt(context: context, courtWidth: courtWidth, courtHeight: courtHeight,
                             scaleX: scaleX, scaleY: scaleY, isLeft: true)
                drawHalfCourt(context: context, courtWidth: courtWidth, courtHeight: courtHeight,
                             scaleX: scaleX, scaleY: scaleY, isLeft: false)
            }
        }
    }
    
    private func drawHalfCourt(context: GraphicsContext, courtWidth: CGFloat, courtHeight: CGFloat,
                               scaleX: CGFloat, scaleY: CGFloat, isLeft: Bool) {
        let basketX = isLeft ? 4.0 * scaleX : courtWidth - 4.0 * scaleX
        let basketY = courtHeight / 2
        
        // Key
        let keyWidth = 16.0 * scaleY
        let keyDepth = 19.0 * scaleX
        let keyTop = (courtHeight - keyWidth) / 2
        
        var keyPath = Path()
        if isLeft {
            keyPath.addRect(CGRect(x: 0, y: keyTop, width: keyDepth, height: keyWidth))
        } else {
            keyPath.addRect(CGRect(x: courtWidth - keyDepth, y: keyTop, width: keyDepth, height: keyWidth))
        }
        context.stroke(keyPath, with: .color(lineColor), lineWidth: lineWidth)
        
        // Free throw circle
        let ftCircleRadius = 6.0 * scaleY
        let ftCircleX = isLeft ? keyDepth : courtWidth - keyDepth
        let ftCircle = Path(ellipseIn: CGRect(
            x: ftCircleX - ftCircleRadius,
            y: basketY - ftCircleRadius,
            width: ftCircleRadius * 2,
            height: ftCircleRadius * 2
        ))
        context.stroke(ftCircle, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, dash: [4, 4]))
        
        // Three-point line
        let threePointRadius = 23.75 * scaleX
        let cornerThreeY = 3.0 * scaleY
        let cornerThreeDepth = 14.0 * scaleX
        
        var threePath = Path()
        if isLeft {
            threePath.move(to: CGPoint(x: 0, y: cornerThreeY))
            threePath.addLine(to: CGPoint(x: cornerThreeDepth, y: cornerThreeY))
            threePath.addArc(center: CGPoint(x: basketX, y: basketY), radius: threePointRadius,
                           startAngle: .degrees(-68), endAngle: .degrees(68), clockwise: false)
            threePath.addLine(to: CGPoint(x: 0, y: courtHeight - cornerThreeY))
        } else {
            threePath.move(to: CGPoint(x: courtWidth, y: cornerThreeY))
            threePath.addLine(to: CGPoint(x: courtWidth - cornerThreeDepth, y: cornerThreeY))
            threePath.addArc(center: CGPoint(x: basketX, y: basketY), radius: threePointRadius,
                           startAngle: .degrees(-112), endAngle: .degrees(112), clockwise: true)
            threePath.addLine(to: CGPoint(x: courtWidth, y: courtHeight - cornerThreeY))
        }
        context.stroke(threePath, with: .color(lineColor), lineWidth: lineWidth)
        
        // Restricted area
        let restrictedRadius = 4.0 * scaleX
        var restrictedPath = Path()
        if isLeft {
            restrictedPath.addArc(center: CGPoint(x: basketX, y: basketY), radius: restrictedRadius,
                                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        } else {
            restrictedPath.addArc(center: CGPoint(x: basketX, y: basketY), radius: restrictedRadius,
                                 startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: false)
        }
        context.stroke(restrictedPath, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, dash: [3, 3]))
        
        // Backboard
        let backboardWidth = 6.0 * scaleY
        var backboardPath = Path()
        backboardPath.move(to: CGPoint(x: basketX, y: basketY - backboardWidth / 2))
        backboardPath.addLine(to: CGPoint(x: basketX, y: basketY + backboardWidth / 2))
        context.stroke(backboardPath, with: .color(lineColor), lineWidth: 2)
        
        // Rim
        let rimRadius = 0.75 * scaleX
        let rimX = isLeft ? basketX + 0.5 * scaleX : basketX - 0.5 * scaleX
        let rimCircle = Path(ellipseIn: CGRect(
            x: rimX - rimRadius, y: basketY - rimRadius,
            width: rimRadius * 2, height: rimRadius * 2
        ))
        context.stroke(rimCircle, with: .color(lineColor), lineWidth: 1.5)
    }
}

// MARK: - Player Marker View
struct PlayerMarkerView: View {
    let player: CourtPlayer
    let isSelected: Bool
    let courtSize: CGSize
    let courtOrigin: CGPoint
    
    var playerColor: Color {
        player.team == .offense ? .white : .yellow
    }
    
    var body: some View {
        let x = courtOrigin.x + player.position.x * courtSize.width
        let y = courtOrigin.y + player.position.y * courtSize.height
        
        ZStack {
            // Selection glow
            if isSelected {
                Circle()
                    .fill(playerColor.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .blur(radius: 4)
            }
            
            // Player circle with glass effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [playerColor, playerColor.opacity(0.8)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            
            // Ball indicator
            if player.hasBall {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
                    .shadow(color: .orange.opacity(0.5), radius: 3)
                    .offset(x: 14, y: -14)
            }
            
            // Number
            if let number = player.number {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }
        }
        .position(x: x, y: y)
    }
}

// MARK: - Arrow Head Shape
struct ArrowHead: Shape {
    let start: CGPoint
    let end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        path.move(to: end)
        path.addLine(to: point1)
        path.addLine(to: point2)
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Mini Court Preview (for MacCoachResourcesView)
struct MiniCourtPreview: View {
    let frame: CourtFrame
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.black)
                
                Rectangle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    .padding(2)
                
                // Half court line
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 0.5)
                
                ForEach(frame.players) { player in
                    Circle()
                        .fill(player.team == .offense ? Color.white : Color.yellow)
                        .frame(width: 4, height: 4)
                        .position(
                            x: player.position.x * geometry.size.width,
                            y: player.position.y * geometry.size.height
                        )
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    BasketballCourtLabView(
        scheme: .constant(CourtScheme(name: "Test Play")),
        onSave: { _ in }
    )
    .environmentObject(DataManager.shared)
    .frame(width: 1100, height: 750)
}
