# Hoopwise — App Store Connect metadata

Paste-ready text for the App Store Connect listing. Fields in [brackets]
need the owner's real details before submission.

## App record

| Field | Value |
|---|---|
| Name (30 max) | Hoopwise |
| Bundle ID | OKTO.SAMp (legacy, must not change: provisioning and the iCloud container depend on it) |
| SKU | hoopwise-ios |
| Primary language | English (U.S.) |
| Version | 2 (MARKETING_VERSION), build 2 (CURRENT_PROJECT_VERSION). Bump the build number on every upload. |
| Primary category | Sports |
| Secondary category | Productivity |
| Price | [Free or paid — owner decision] |

If "Hoopwise" is already taken on the App Store, App Store Connect rejects
the name at record creation. Fallbacks: "Hoopwise Coach", "Hoopwise Academy".

## Subtitle (30 max)
Basketball coaching, organized

## Promotional text (170 max, editable without review)
Plan sessions, take attendance, and track every prepaid session for your basketball academy — synced privately through your own iCloud.

## Description (4000 max)

Hoopwise is a coaching operations app for basketball coaches and academies. It keeps your athletes, programs, sessions, attendance and session bundles in one place, and syncs them privately through your own iCloud account.

PROGRAMS AND SESSIONS
• Build training programs with phases, and generate their sessions on a schedule
• Sessions name themselves from their program and phase
• Skip a session with a reason; it stays in your calendar and refunds anything it consumed

ATTENDANCE THAT MATCHES THE MONEY
• Four clear states: present, excused, absent, and not yet marked
• Every row tells you whether it deducts a session from the athlete's bundle
• Unmarked never charges; excused never charges

CONTRACTS AND BUNDLES
• Prepaid session bundles, consumed in purchase order
• Payment ledger with partial payments and travel fees
• Record when an agreement was signed and when kit was handed out
• Media consent recorded as a dated history, including withdrawals

DOCUMENTS
• Export a one-page attendance statement for a family
• Export the training agreement, blank for signing or filled from a contract
• Share as PDF through any app, including WeChat

AT A GLANCE
• Home screen widgets: next session, today, needs attention, and weekly cadence
• Live Activity on the Lock Screen while a session is running
• An attention list limited to the few things that need action in the next two days

ATHLETES
• Profiles with photos, birth date or school grade, measurements and guardian contacts
• Attendance rate per athlete, counted only from sessions you actually marked

LANGUAGES
• English and Chinese (中文), switchable inside the app

PRIVATE BY DESIGN
• No account to create and no sign-in
• Your data stays on your device and in your own iCloud. The developer cannot see it
• No ads, no tracking, no analytics

## Keywords (100 max, comma-separated, no spaces after commas)
basketball,coach,academy,attendance,training,sessions,drills,roster,team,youth,bundle,contracts

## Support URL
[https://your-domain/support]  — must be a live page with a way to contact you.

## Marketing URL (optional)
[https://your-domain]

## Privacy Policy URL (required)
[https://your-domain/privacy]  — host AppStore/privacy-policy.md there.

## Copyright
© 2026 [Legal name of the person or company publishing the app]

## Age rating questionnaire
Answer "None" / "No" to every content question. The app has no user-generated
content shared between users, no chat, no web browsing, and no purchases.
Expected result: 4+.

## App Privacy (the "nutrition label")
Answer: **Data Not Collected.**
Reason: the developer receives no data. Everything is stored on the device
and in the user's iCloud private database, which only the user can read.
No analytics, crash-reporting or advertising SDKs are included.
This must stay consistent with Hoopwise/PrivacyInfo.xcprivacy.

## Export compliance
Info.plist sets ITSAppUsesNonExemptEncryption = NO. The app uses only
Apple's HTTPS and SHA-256 hashing, which are exempt. App Store Connect will
not ask the encryption question on each upload.

## Notes for App Review
Hoopwise has no login. It opens to an empty academy, so the reviewer can test
everything from scratch:
1. Athletes tab → add two athletes.
2. Sessions tab → create a program, then a session in it for today.
3. Open the session and take attendance: mark one athlete present and one
   excused. Each row states whether it deducts a session.
4. Add a Hoopwise widget to the home screen to see the next session.
[Owner: walk these four steps on a fresh install and correct any label
that differs before pasting this into App Store Connect.]
iCloud is optional. Without an iCloud account the app works fully on-device.
Camera, photo library, microphone and speech recognition are only requested
when the coach adds an athlete photo or dictates a session note.

## What's New (version 2)
First App Store release.
