# Supabase Cloud Sync Setup Guide

This guide will walk you through setting up Supabase for cross-platform data sync between iOS and macOS.

---

## Step 1: Create a Supabase Account

1. Go to [https://supabase.com](https://supabase.com)
2. Click **"Start your project"** (top right)
3. Sign up with:
   - GitHub (recommended)
   - Or email/password

---

## Step 2: Create a New Project

1. After signing in, click **"New Project"**
2. Fill in the details:
   - **Name**: `SAM` (or any name you prefer)
   - **Database Password**: Create a strong password (save this somewhere safe!)
   - **Region**: Choose the closest to you (e.g., `Southeast Asia (Singapore)`)
3. Click **"Create new project"**
4. ⏳ Wait 1-2 minutes for the project to be provisioned

---

## Step 3: Get Your Project Credentials

Once your project is ready:

1. Click **"Project Settings"** (gear icon in the left sidebar)
2. Click **"API"** in the settings menu
3. You'll see two important values:
   - **Project URL**: `https://xxxxxxxx.supabase.co`
   - **anon public key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

4. **Copy both values** - you'll need them in Step 5

---

## Step 4: Create the Database Tables

1. In your Supabase dashboard, click **"SQL Editor"** in the left sidebar
2. Click **"New query"**
3. Open the file `supabase_schema.sql` in this project folder
4. **Copy the entire contents** of that file
5. **Paste it** into the SQL Editor
6. Click **"Run"** (or press Cmd+Enter)
7. You should see: `SAM database schema created successfully!`

### Verify Tables Were Created

1. Click **"Table Editor"** in the left sidebar
2. You should see these tables:
   - `students`
   - `players`
   - `contracts`
   - `programs`
   - `micro_cycles`
   - `session_events`
   - `measurements`
   - `drills`

---

## Step 5: Update the App Configuration

1. Open Xcode
2. Navigate to: `SAM/Managers/SupabaseManager.swift`
3. Find lines 7-9:

```swift
struct SupabaseConfig {
    static let url = "https://mgovivfcudovnejyiaau.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

4. **Replace** with your values from Step 3:

```swift
struct SupabaseConfig {
    static let url = "https://YOUR-PROJECT-ID.supabase.co"  // Your Project URL
    static let anonKey = "YOUR-ANON-KEY"                     // Your anon public key
}
```

5. **Save the file** (Cmd+S)

---

## Step 6: Build and Test

1. Build the app (Cmd+B)
2. Run the app (Cmd+R)
3. Check the Xcode console for:
   ```
   ✅ Supabase connected successfully
   ```

If you see this, cloud sync is working! 🎉

---

## Step 7: Verify Sync is Working

### On macOS:
1. Look at the bottom of the sidebar
2. The sync button (circular arrows) should be **green**
3. Click it to manually sync

### Test Cross-Platform Sync:
1. Add a student on macOS
2. Wait a few seconds (or click sync)
3. Open the iOS app
4. The student should appear!

---

## Troubleshooting

### "Cloud sync unavailable" message
- Check your internet connection
- Verify the Project URL is correct (no typos)
- Make sure the anon key is complete (it's very long)

### "Server error 401"
- The anon key is incorrect
- Copy it again from Supabase dashboard

### "Server error 404" or tables not found
- The SQL schema wasn't run
- Go back to Step 4 and run the SQL again

### Data not syncing
- Check if the sync button is green (connected)
- Try clicking the sync button manually
- Check Xcode console for error messages

---

## How Sync Works

| Event | Action |
|-------|--------|
| App launches | Connects to Supabase → Downloads cloud data |
| App becomes active | Refreshes from cloud |
| App goes to background | Uploads local changes to cloud |
| Any data change | Automatically uploads to cloud |
| Manual sync button | Full sync (both directions) |

### Conflict Resolution
- Uses **last-write-wins** based on `updated_at` timestamp
- The most recently modified version is kept

---

## Security Notes

⚠️ The current setup uses the **anon key** which allows public access. This is fine for development but for production you should:

1. Enable Row Level Security (RLS) in Supabase
2. Set up user authentication
3. Create proper RLS policies

The schema file includes commented-out RLS setup that you can enable later.

---

## Need Help?

- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Discord](https://discord.supabase.com)
