-- ============================================
-- HOOPWISE MASTER MIGRATION - February 2026
-- ============================================
-- This migration consolidates ALL schema changes needed for full Supabase sync.
-- Run this ONCE on your Supabase project to ensure complete schema compatibility.
-- 
-- IMPORTANT: This migration is IDEMPOTENT (safe to run multiple times)
-- ============================================

-- ============================================
-- STUDENTS TABLE - New Columns
-- ============================================

-- Age input fields (month/year mode)
ALTER TABLE students ADD COLUMN IF NOT EXISTS birth_month INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS birth_year INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS school_grade TEXT;

-- Tracking fields
ALTER TABLE students ADD COLUMN IF NOT EXISTS created_by_coach_id UUID;
ALTER TABLE students ADD COLUMN IF NOT EXISTS parental_touchpoints_json TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS last_parent_contact TIMESTAMPTZ;

-- Media assets
ALTER TABLE students ADD COLUMN IF NOT EXISTS media_assets_json TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS personal_bests_json TEXT;

-- Performance grade (A/B/C peer comparison)
ALTER TABLE students ADD COLUMN IF NOT EXISTS performance_grade TEXT;

-- ============================================
-- PLAYERS TABLE - New Columns
-- ============================================

-- Header image for profile card
ALTER TABLE players ADD COLUMN IF NOT EXISTS header_image_url TEXT;

-- ============================================
-- CONTRACTS TABLE - New Columns
-- ============================================

-- Manual status override
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS manual_status TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS created_by_coach_id UUID;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS program_assignments_json TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS enrollment_date TIMESTAMPTZ;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS attended_session_ids_json TEXT;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS historical_sessions_consumed INTEGER DEFAULT 0;

-- Migrate existing attended_sessions to historical baseline (only if not already done)
UPDATE contracts 
SET historical_sessions_consumed = attended_sessions 
WHERE historical_sessions_consumed = 0 AND attended_sessions > 0;

-- ============================================
-- PROGRAMS TABLE - New Columns
-- ============================================

ALTER TABLE programs ADD COLUMN IF NOT EXISTS uses_phases BOOLEAN DEFAULT true;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS skill_targets_json TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS recurring_days_json TEXT;

-- ============================================
-- SESSION_EVENTS TABLE - New Columns
-- ============================================

ALTER TABLE session_events ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS excused_absences UUID[] DEFAULT '{}';
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS attendance_photo_path TEXT;
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS development_focus TEXT[] DEFAULT '{}';
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS games JSONB DEFAULT '[]';

-- ============================================
-- STAFF_COACHES TABLE - New Columns
-- ============================================

ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS chinese_name TEXT;
ALTER TABLE staff_coaches ADD COLUMN IF NOT EXISTS organization_id UUID;

-- ============================================
-- ORGANIZATIONS TABLE (if not exists)
-- ============================================
-- Required for multi-organization support

CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    chinese_name TEXT,
    logo_url TEXT,
    primary_color_hex TEXT DEFAULT '#3B82F6',
    secondary_color_hex TEXT DEFAULT '#1E40AF',
    owner_user_id UUID,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Organization memberships (coaches belonging to organizations)
CREATE TABLE IF NOT EXISTS organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL DEFAULT 'coach',  -- owner, admin, coach, assistant
    permissions JSONB DEFAULT '{}',
    invited_by UUID,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organization_id, user_id)
);

-- ============================================
-- ADD ORGANIZATION_ID TO ALL TABLES (for multi-org filtering)
-- ============================================

ALTER TABLE students ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE players ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE micro_cycles ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE drills ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE locations ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE plays ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE games ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS organization_id UUID;

-- ============================================
-- INDEXES for performance
-- ============================================

CREATE INDEX IF NOT EXISTS idx_students_organization ON students(organization_id);
CREATE INDEX IF NOT EXISTS idx_players_organization ON players(organization_id);
CREATE INDEX IF NOT EXISTS idx_contracts_organization ON contracts(organization_id);
CREATE INDEX IF NOT EXISTS idx_programs_organization ON programs(organization_id);
CREATE INDEX IF NOT EXISTS idx_session_events_organization ON session_events(organization_id);
CREATE INDEX IF NOT EXISTS idx_session_events_program_status ON session_events(program_id, status);
CREATE INDEX IF NOT EXISTS idx_students_school_grade ON students(school_grade);
CREATE INDEX IF NOT EXISTS idx_students_birth_year ON students(birth_year);
CREATE INDEX IF NOT EXISTS idx_organization_members_user ON organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_organization_members_org ON organization_members(organization_id);

-- ============================================
-- TRIGGERS for updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_organizations_updated_at ON organizations;
CREATE TRIGGER update_organizations_updated_at 
BEFORE UPDATE ON organizations 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_organization_members_updated_at ON organization_members;
CREATE TRIGGER update_organization_members_updated_at 
BEFORE UPDATE ON organization_members 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Run these to verify the migration was successful:

-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'students' ORDER BY ordinal_position;
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'contracts' ORDER BY ordinal_position;
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'session_events' ORDER BY ordinal_position;
-- SELECT * FROM organizations LIMIT 1;
-- SELECT * FROM organization_members LIMIT 1;

-- ============================================
-- SUCCESS
-- ============================================
SELECT 'Hoopwise master migration completed successfully!' as message;
