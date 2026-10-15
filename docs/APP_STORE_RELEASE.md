# iOS App Store release — checklist

October 2026. First App Store release of the iOS app (bundle OKTO.SAMp,
version 2, build 2). Work top to bottom. Section 1 holds decisions only the
owner can make; nothing after it should start until they are settled.

## 1. Owner decisions (blocking)

### 1a. Where the real data goes — THE BIG ONE
A released build (TestFlight or App Store) reads the CloudKit **Production**
database. Every record entered so far lives in **Development**, because only
debug builds have ever run (CLAUDE.md, "macOS gotchas"). Deploying the schema
copies the record TYPES, never the data. On first launch of the released
app, the academy will be empty: no athletes, programs, sessions or contracts.

The existing `.hoopwise` bundle cannot carry it across. Bundle v1 holds
students, drills, staff coaches, locations and attendance snapshots. It has
no programs, phases, sessions, contracts, payments, consents, plays or
directory groups.

Options:
1. **Extend the bundle to the whole store**, export from a debug build,
   import into the released build. Plumbing only: no schema change, and the
   import/export UI already exists in the Hub, so the iOS UI freeze is not
   touched. This is code work that must be built and verified on the Mac.
2. **Re-enter the data** in the released build.
3. **Keep the academy on debug builds** and publish the App Store version for
   other coaches, who start empty anyway.

### 1b. iPhone only, or iPhone and iPad
The target is universal (TARGETED_DEVICE_FAMILY = 1,2). That requires 13" iPad
screenshots, and App Review will exercise the iPad layout. If the iPad layout
is not ready, set the family to 1 before the first upload. Removing iPad
support after release is not allowed for existing users.

### 1c. Listing details
Legal publisher name, price, support URL, privacy policy URL and contact
email. The text is ready in `AppStore/metadata.md` and
`AppStore/privacy-policy.md`; every [bracket] needs a real value. The
privacy policy must be hosted at a public URL before submission.

## 2. Done in the repository (October 2026)
- `Hoopwise/PrivacyInfo.xcprivacy`: privacy manifest, iOS target only.
  Declares no tracking and no collected data, plus the two required-reason
  APIs the app calls: UserDefaults (CA92.1) and file timestamps (C617.1).
  Without it App Store Connect rejects the upload (ITMS-91053).
- `Hoopwise/Info.plist`:
  - `ITSAppUsesNonExemptEncryption = NO`, so every upload skips the
    encryption question.
  - `LSSupportsOpeningDocumentsInPlace = NO`, which the `.hoopwise`
    document type needs (otherwise App Store Connect flags ITMS-90737 on upload).
- `AppStore/metadata.md`, `AppStore/privacy-policy.md` and
  `AppStore/screenshots-guide.md` rewritten for the current app: iCloud
  sync, no accounts, four-state attendance, current screenshot sizes. The
  old text described Supabase accounts and the name "Clutch".

Audited and fine as is:
- Every HOOPWISE_* debug environment hook is inside `#if DEBUG`.
- App icon: single 1024×1024 PNG, no alpha channel.
- No third-party packages, so no third-party privacy manifests are needed.
- `aps-environment = development` in the entitlements is correct.
  Automatic signing switches it to production when exporting for the store.
- No account system, so the account-deletion rule (5.1.1(v)) does not apply.
- `UnsplashConfig` calls `fatalError` in Release when the key is missing,
  but its only caller (`fetchBasketballImages`) is never called. Not a
  crash today. Do not wire it up without adding the key.

## 3. Verify on the Mac before archiving
1. **Widget minimum iOS.** DONE 2026-10-15: the widget was lowered to 26.1
   to match the app; it builds for simulator and device, and the archive
   reports MinimumOSVersion 26.1 for both bundles.
2. **No API keys in the iOS app.** The iOS target uses
   `Configuration.xcconfig` as its base configuration, and that file holds
   the Anthropic/Gemini/Groq keys. If it defines `INFOPLIST_KEY_*` entries
   globally, the keys land in the shipped iOS Info.plist, where anyone can
   read them. After archiving, check:
   ```
   plutil -p ~/Library/Developer/Xcode/Archives/*/*/Hoopwise*.xcarchive/Products/Applications/Hoopwise.app/Info.plist | grep -iE "key|api"
   ```
   Any API key in the output must be removed from the iOS target before
   uploading. The Whistle assistant is Mac-only, so iOS needs none.
   CHECKED 2026-10-15: Info.plist was clean, but `Configuration.xcconfig`
   ITSELF was in the iOS target's Copy Bundle Resources phase, so every iOS
   build shipped the three keys as a readable file in the bundle. Removed
   from the phase (it remains the base configuration). A re-archive contains
   no xcconfig and no key prefix in any file, binaries included. Re-check
   with `ls Hoopwise.app | grep xcconfig` on every archive. The keys that
   shipped in earlier debug installs should be treated as exposed only if
   such a build left the coach's own devices.
3. **Build numbers match.** The app and the widget must share the same
   CURRENT_PROJECT_VERSION (both 2 today). Bump both on every upload.
4. **Tests green.** ⌘U on the Hoopwise scheme, using the sequential
   pre-booted-simulator procedure in CLAUDE.md.
5. **Privacy manifest is in the bundle.** After a build, confirm
   `PrivacyInfo.xcprivacy` sits in `Hoopwise.app`. It should land there
   automatically through the synchronized Hoopwise folder.

## 4. Deploy the CloudKit schema (rule 7d) — irreversible
Production schemas are additive only. Whatever is deployed stays forever.

1. Run the iOS app AND the Mac app once in Debug, so Development has seen
   every type and field (rule 7c).
2. Open https://icloud.developer.apple.com → container
   `iCloud.com.hoopwise.Hoopwise` → Development → "Deploy Schema Changes…".
3. Read the change list. It should include the four pending fields
   (`SDSessionEvent.seriesId`, `SDContract.signedDate`, `jerseyGivenDate`,
   `ballGivenDate`) and every registered record type: Coach, ConceptLink,
   ConceptNode, Contract, DirectoryGroup, Drill, DrillMedia, EntityRevision,
   Game, ImportLog, Location, Measurement, MicroCycle, Play, PlayDiagram,
   Player, Program, Reminder, School, SessionEvent, StaffCoach, Student,
   Team, AppSettings. The knowledge-base types (Concept*, EntityRevision)
   become permanent here even though that feature is not built. That is
   the intended "define once, deploy once" path.
4. Deploy to Production.

## 5. Archive and upload
1. Xcode: scheme **Hoopwise**, destination **Any iOS Device (arm64)**.
2. Product → Archive. `Configuration.xcconfig` must exist locally or the
   build fails.
3. Run the key check from step 3.2 against the new archive.
4. Organizer → Distribute App → App Store Connect → Upload.
5. Wait for the processing email. A rejection email names the exact
   problem (ITMS-xxxxx).

## 6. App Store Connect
1. Create the app record: bundle ID OKTO.SAMp, name, SKU, primary language.
2. TestFlight: install on your own iPhone first. This is the first time the
   app touches Production, so confirm launch, widgets, the Live Activity and
   iCloud sync between two devices before submitting.
3. Fill in the listing from `AppStore/metadata.md`: subtitle, description,
   keywords, URLs, category, copyright.
4. App Privacy: "Data Not Collected".
5. Age rating questionnaire: all "None" → 4+.
6. Screenshots per `AppStore/screenshots-guide.md`, using demo data only.
   The real roster is minors. FIRST SET CAPTURED 2026-10-15: 6.9" iPhone,
   English and Chinese, 8 each (home, attendance, parent guide, program,
   calendar, athlete, hub, athletes), from the isolated demo store — see
   CLAUDE.md "App Store screenshots" for the repeatable procedure. Still
   owed: iPad 13" (or go iPhone-only, 1b), Chinese demo CONTENT for the
   Chinese set, captions/frames.
7. App Review notes from `AppStore/metadata.md`, after walking the four
   steps on a fresh install.
8. Submit for review.

## 7. After release
- Debug builds keep using Development. A debug build never sees what the
  released app writes, and the reverse is also true.
- Any future schema change repeats section 4, and an iOS build carrying
  the change must ship before the Mac writes it (rule 7e).
