# Attendance Photo Feature Documentation

## Overview
Automatic session status transitions with attendance photo capture and compression to minimize storage usage.

## Features

### 1. Automatic Session Status Transitions
- **Scheduled → In Progress**: Automatically when `startTime` is reached
- **In Progress → Completed**: Automatically when `endTime` is reached
- **Monitoring Interval**: Every 30 seconds
- **Live Activity Integration**: iOS only - shows session progress on lock screen

### 2. Attendance Photo Capture
- **Trigger**: Automatically shown when session completes
- **Compression**: Aggressive JPEG compression (~200KB per photo)
- **Storage**: Local only (Documents/AttendancePhotos/)
- **Path Sync**: File path synced to Supabase, not the photo itself

### 3. Storage Optimization
- **Original Photo Size**: 2-5 MB (typical)
- **Compressed Photo Size**: ~200 KB (90-95% reduction)
- **100 Sessions**: ~20 MB vs ~300 MB (saves 280 MB!)
- **Compression Strategy**:
  - Resize to max 1024px width
  - JPEG quality 0.5
  - Progressive compression if needed

## Database Schema

### Supabase Table: `session_events`
```sql
ALTER TABLE session_events
ADD COLUMN attendance_photo_path TEXT;
```

### SwiftData Model: `SDSessionEvent`
```swift
var attendancePhotoPath: String?
```

### Session Model: `SessionEvent`
```swift
var attendancePhotoPath: String? // Local path to compressed attendance photo
```

## Organization Filtering

All session data, including attendance photo paths, are properly filtered by organization:

1. **SupabaseSessionEvent DTO** includes `organizationId` from `AuthManager.shared.currentOrganization?.id`
2. **RLS Policies** in Supabase ensure users only see their organization's data
3. **Photo paths** are organization-specific (each org has separate local storage)

## File Structure

### New Files
1. **SessionStatusMonitor.swift** - Monitors and auto-transitions session status
2. **PhotoCaptureManager.swift** - Handles photo capture and compression
3. **AttendanceReminderSheet.swift** - UI for attendance + photo capture

### Modified Files
1. **Session.swift** - Added `attendancePhotoPath` property
2. **SDSessionEvent.swift** - Added SwiftData persistence
3. **SupabaseDTOs.swift** - Added Supabase sync
4. **SwiftDataManager.swift** - Added property update
5. **SAMApp.swift** - Integrated monitor service
6. **MainTabView.swift** - Added reminder sheet

## Usage

### Automatic Flow
1. Session starts → Status: "In Progress"
2. Live Activity starts (iOS)
3. Session ends → Status: "Completed"
4. Live Activity ends (iOS)
5. Reminder sheet appears
6. Coach takes attendance + photo
7. Photo compressed to ~200KB
8. Path saved to database
9. Synced to Supabase

### Manual Control
```swift
// Start session manually
SessionStatusMonitor.shared.startSession(session)

// Complete session manually
SessionStatusMonitor.shared.completeSession(session)
```

### Photo Management
```swift
// Save photo
let path = PhotoCaptureManager.shared.saveAttendancePhoto(image, for: sessionId)

// Load photo
let image = PhotoCaptureManager.shared.loadAttendancePhoto(from: path)

// Delete photo
PhotoCaptureManager.shared.deleteAttendancePhoto(at: path)

// Get total storage
let size = PhotoCaptureManager.shared.getAttendancePhotosSize()
```

## Migration Steps

### 1. Run SQL Migration
Execute `add_attendance_photo_column.sql` in Supabase SQL Editor:
```sql
ALTER TABLE session_events
ADD COLUMN IF NOT EXISTS attendance_photo_path TEXT;
```

### 2. Verify RLS Policies
Ensure existing RLS policies on `session_events` table include the new column.

### 3. Test Flow
1. Create a test session with start/end times close together
2. Wait for automatic status transitions
3. Verify attendance reminder appears
4. Take a test photo
5. Verify photo is compressed (~200KB)
6. Verify path syncs to Supabase
7. Verify organization filtering works

## Storage Considerations

### Local Storage
- Photos stored in: `Documents/AttendancePhotos/`
- Filename format: `attendance_{sessionId}.jpg`
- Compression target: 200KB per photo
- No automatic cleanup (photos persist)

### Cloud Storage
- **Only file paths** are synced to Supabase
- **Photos are NOT uploaded** to cloud storage
- This minimizes Supabase storage costs
- Each organization has separate photo paths

### Future Enhancements
- Optional cloud backup to Supabase Storage
- Automatic cleanup of old photos (>6 months)
- Photo gallery view in session detail
- Bulk export of attendance photos

## Security & Privacy

### Organization Isolation
- Each organization's photos are isolated
- RLS policies prevent cross-org access
- Photo paths include organization context

### Data Protection
- Photos stored locally only
- No automatic cloud upload
- Coach controls when to take photos
- Photos can be deleted anytime

## Performance

### Monitoring Impact
- Checks every 30 seconds
- Minimal CPU usage
- No network calls during monitoring
- Only updates when status changes

### Photo Compression
- Compression happens on main thread
- Takes ~100-200ms per photo
- User sees progress indicator
- Non-blocking UI

## Troubleshooting

### Session not auto-transitioning
- Check SessionStatusMonitor is started in SAMApp
- Verify session times are correct
- Check console logs for errors

### Photo not saving
- Check camera permissions
- Verify Documents directory access
- Check console for compression errors

### Photo not syncing
- Verify Supabase connection
- Check organizationId is set
- Verify RLS policies allow insert/update

## API Reference

### SessionStatusMonitor
```swift
class SessionStatusMonitor: ObservableObject {
    static let shared: SessionStatusMonitor
    
    func startMonitoring(dataManager: DataManager)
    func stopMonitoring()
    func startSession(_ session: SessionEvent)
    func completeSession(_ session: SessionEvent)
    
    @Published var showAttendanceReminder: Bool
    @Published var completedSession: SessionEvent?
}
```

### PhotoCaptureManager
```swift
class PhotoCaptureManager {
    static let shared: PhotoCaptureManager
    
    func saveAttendancePhoto(_ image: PlatformImage, for sessionId: UUID) -> String?
    func loadAttendancePhoto(from path: String) -> PlatformImage?
    func deleteAttendancePhoto(at path: String)
    func getAttendancePhotosSize() -> String
}
```

### AttendanceReminderSheet
```swift
struct AttendanceReminderSheet: View {
    @State var session: SessionEvent
    // Shows attendance marking + photo capture
    // Compresses and saves photo
    // Updates session in database
}
```
