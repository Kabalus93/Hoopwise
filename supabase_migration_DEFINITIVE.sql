-- ============================================================
-- HOOPWISE — DEFINITIVE ALL-IN-ONE MIGRATION
-- ============================================================
-- This single file ensures your Supabase schema matches EXACTLY
-- what the app's DTOs send. Run this ONCE in your Supabase SQL
-- Editor. It is 100% IDEMPOTENT (safe to run multiple times).
--
-- If ANY column below is missing, the entire batch upload for
-- that table will SILENTLY FAIL with a Supabase 400 error.
-- ============================================================

-- ============================================================
-- 1. STUDENTS TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE students ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE students ADD COLUMN IF NOT EXISTS birth_month INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS birth_year INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS school_grade TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS created_by_coach_id UUID;
ALTER TABLE students ADD COLUMN IF NOT EXISTS parental_touchpoints_json TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS last_parent_contact TIMESTAMPTZ;
ALTER TABLE students ADD COLUMN IF NOT EXISTS media_assets_json TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS personal_bests_json TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS performance_grade TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS grade_history_json TEXT;

-- ============================================================
-- 2. PLAYERS TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE players ADD COLUMN IF NOT EXISTS header_image_url TEXT;

-- ============================================================
-- 3. CONTRACTS TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS enrollment_date TIMESTAMPTZ;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS attended_session_ids_json TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS created_by_coach_id UUID;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS manual_status TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS program_assignments_json TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS historical_sessions_consumed INTEGER DEFAULT 0;

-- ============================================================
-- 4. PROGRAMS TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE programs ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS uses_phases BOOLEAN DEFAULT true;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS skill_targets_json TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS recurring_days_json TEXT;

-- ============================================================
-- 5. SESSION_EVENTS TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS excused_absences UUID[] DEFAULT '{}';
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS attendance_photo_path TEXT;
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS development_focus TEXT[] DEFAULT '{}';
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS games JSONB DEFAULT '[]';
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS created_by_coach_id UUID;
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS board_notes_json TEXT;

-- ============================================================
-- 6. STAFF_COACHES TABLE — all columns the DTO encoder sends
-- ============================================================
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS chinese_name TEXT;
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS access_level TEXT NOT NULL DEFAULT 'Coaching Staff';
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS hire_date TIMESTAMPTZ;
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS profile_image_url TEXT;

-- ============================================================
-- 7. OTHER TABLES — organization_id for multi-org
-- ============================================================
ALTER TABLE micro_cycles ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE drills ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE locations ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE plays ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE games ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS organization_id UUID;

-- ============================================================
-- 8. REMINDERS TABLE — MUST BE CREATED (does not exist yet!)
-- ============================================================
CREATE TABLE IF NOT EXISTS reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID,
    title TEXT NOT NULL,
    note TEXT,
    due_date TIMESTAMPTZ NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    completed_at TIMESTAMPTZ,
    priority TEXT NOT NULL DEFAULT 'medium',
    session_id UUID,
    program_id UUID,
    coach_id UUID NOT NULL,
    creator_coach_id UUID NOT NULL,
    tagged_student_ids UUID[] DEFAULT '{}',
    tagged_coach_ids UUID[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 9. ORGANIZATIONS TABLE (required for multi-org)
-- ============================================================
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    display_name TEXT,
    chinese_name TEXT,
    logo_url TEXT,
    primary_color_hex TEXT DEFAULT '#3B82F6',
    secondary_color_hex TEXT DEFAULT '#1E40AF',
    secret_code TEXT,
    owner_id UUID,
    owner_user_id UUID,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL DEFAULT 'coach',
    permissions JSONB DEFAULT '{}',
    invited_by UUID,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

-- ============================================================
-- 10. USER ACCOUNTS TABLE (for auth)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    password_hash TEXT,
    organization_id UUID,
    role TEXT NOT NULL DEFAULT 'coach',
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 11. AGE CATEGORIES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS age_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    min_age INTEGER,
    max_age INTEGER,
    color_hex TEXT NOT NULL DEFAULT '#3B82F6',
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 12. INDEXES for performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_students_organization ON students(organization_id);
CREATE INDEX IF NOT EXISTS idx_players_organization ON players(organization_id);
CREATE INDEX IF NOT EXISTS idx_contracts_organization ON contracts(organization_id);
CREATE INDEX IF NOT EXISTS idx_programs_organization ON programs(organization_id);
CREATE INDEX IF NOT EXISTS idx_session_events_organization ON session_events(organization_id);
CREATE INDEX IF NOT EXISTS idx_session_events_program_status ON session_events(program_id, status);
CREATE INDEX IF NOT EXISTS idx_students_school_grade ON students(school_grade);
CREATE INDEX IF NOT EXISTS idx_students_birth_year ON students(birth_year);
CREATE INDEX IF NOT EXISTS idx_reminders_organization_id ON reminders(organization_id);
CREATE INDEX IF NOT EXISTS idx_reminders_updated_at ON reminders(updated_at);
CREATE INDEX IF NOT EXISTS idx_reminders_coach_id ON reminders(coach_id);

-- ============================================================
-- 13. TRIGGERS for auto-updating updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_reminders_updated_at ON reminders;
CREATE TRIGGER update_reminders_updated_at 
BEFORE UPDATE ON reminders 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 14. BACKFILL: stamp organization_id on reminders from coach
-- ============================================================
UPDATE reminders r
SET organization_id = sc.organization_id
FROM staff_coaches sc
WHERE r.coach_id = sc.id
  AND r.organization_id IS NULL
  AND sc.organization_id IS NOT NULL;

-- ============================================================
-- 15. VERIFICATION — Run this to confirm all columns exist
-- ============================================================
-- Copy-paste these SELECT queries after running the migration:
--
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'students' ORDER BY ordinal_position;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'session_events' ORDER BY ordinal_position;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'contracts' ORDER BY ordinal_position;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'staff_coaches' ORDER BY ordinal_position;
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'reminders' ORDER BY ordinal_position;

-- ============================================================
-- SUCCESS
-- ============================================================
SELECT 'Hoopwise DEFINITIVE migration completed! All tables are now in sync with app DTOs.' as message;
