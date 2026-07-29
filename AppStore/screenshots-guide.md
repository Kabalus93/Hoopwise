# Hoopwise - App Store Screenshots Guide

## Required Screenshot Sizes

### iPhone (Required)
| Device | Resolution | Display Size |
|--------|------------|--------------|
| iPhone 15 Pro Max / 14 Pro Max | 1290 x 2796 px | 6.7" |
| iPhone 15 Pro / 14 Pro | 1179 x 2556 px | 6.1" |
| iPhone 8 Plus (if supporting older) | 1242 x 2208 px | 5.5" |

### iPad (Required if universal app)
| Device | Resolution |
|--------|------------|
| iPad Pro 12.9" (6th gen) | 2048 x 2732 px |
| iPad Pro 11" | 1668 x 2388 px |

## Screenshot Count
- **Minimum**: 3 screenshots per device size
- **Maximum**: 10 screenshots per device size
- **Recommended**: 5-6 screenshots showcasing key features

---

## Recommended Screenshots (in order)

### Screenshot 1: Hero/Dashboard
**Caption (EN)**: "Your Coaching Dashboard"
**Caption (中文)**: "教练仪表板"
- Show the main dashboard/home screen
- Highlight upcoming sessions, student overview
- Best if showing Live Activity session in progress

### Screenshot 2: Session Detail
**Caption (EN)**: "Smart Session Planning"
**Caption (中文)**: "智能课程规划"
- Show the FlightySessionPageView with hero card
- Display drill breakdown (Warmup, Skills, Game)
- Show the beautiful map background

### Screenshot 3: Student Management
**Caption (EN)**: "Manage Your Athletes"
**Caption (中文)**: "管理您的学员"
- Show student list or student detail view
- Display student avatars and categories
- Highlight the organized layout

### Screenshot 4: Add Student
**Caption (EN)**: "Easy Student Enrollment"
**Caption (中文)**: "轻松添加学员"
- Show AddStudentView with the new age input
- Display school grade picker or birth date selector
- Show profile photo option

### Screenshot 5: Attendance Tracking
**Caption (EN)**: "Real-Time Attendance"
**Caption (中文)**: "实时考勤追踪"
- Show attendance view during a session
- Display present/absent/late status indicators
- Show quick-tap attendance marking

### Screenshot 6: Programs & Curriculum
**Caption (EN)**: "Structured Training Programs"
**Caption (中文)**: "结构化训练计划"
- Show program detail with phases
- Display micro-cycles and sessions
- Highlight curriculum organization

---

## Screenshot Design Tips

### Do's ✅
- Use real (or realistic) demo data
- Show the app in a clean state with good content
- Use consistent device frames
- Add brief, impactful captions
- Show both English and Chinese versions (localized screenshots)
- Capture in Light mode (more appealing for App Store)
- Use high-quality student avatars/photos

### Don'ts ❌
- Don't show empty states
- Don't include personal/real student data
- Don't use cluttered screens
- Don't show error messages or loading states
- Don't use placeholder text like "Lorem ipsum"

---

## How to Capture Screenshots

### On Simulator
```bash
# Open Simulator, navigate to desired screen, then:
# Cmd + S to save screenshot to Desktop
```

### On Physical Device
- Navigate to the screen
- Press **Side Button + Volume Up** simultaneously
- Screenshots save to Photos app

### Using Xcode
1. Run app on desired simulator
2. Debug → View Debugging → Take Screenshot

---

## Screenshot Frame Tools

Consider using these tools to add device frames and captions:

- **Screenshots Pro** (Mac App Store) - Easy device frames
- **Rotato** - 3D device mockups
- **Figma** - Free, flexible design
- **Canva** - Quick and easy templates
- **AppMockUp** (appmockup.io) - Free online tool

---

## Localized Screenshots

Since Clutch supports Chinese and English, consider uploading localized screenshots:

1. Set device language to Chinese
2. Capture all screenshots
3. Upload to Chinese (Simplified) localization in App Store Connect
4. Repeat for English

---

## App Preview Video (Optional but Recommended)

- **Duration**: 15-30 seconds
- **Resolution**: Same as screenshot sizes
- **Content Ideas**:
  - Quick tour: Dashboard → Session → Attendance → Back
  - Show Live Activity appearing
  - Demonstrate adding a student
  - Show session planning flow

---

## Sample Demo Data for Screenshots

Create appealing demo data:
- **Students**: "Alex Chen", "Emma Liu", "Jordan Wu", "Sofia Wang"
- **Programs**: "Tigers U12", "Elite Skills", "Summer Camp 2026"
- **Sessions**: "Dribbling Fundamentals", "Shooting Masterclass", "Game Day Prep"
- **Coaches**: Use professional-looking names

---

## Checklist Before Submission

- [ ] All required device sizes have screenshots
- [ ] Screenshots are high resolution (no blur)
- [ ] No personal/real data visible
- [ ] App name visible in status bar matches "Clutch"
- [ ] Time shown is clean (9:41 AM is Apple's traditional time)
- [ ] Battery shows 100% or near full
- [ ] No low battery warnings
- [ ] Cellular shows full signal
- [ ] Chinese screenshots uploaded to Chinese localization
