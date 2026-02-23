-- ============================================
-- SAM (Sports Academy Manager) - Supabase Schema
-- ============================================
-- Run this SQL in your Supabase SQL Editor to create all required tables
-- 
-- INSTRUCTIONS:
-- 1. Go to your Supabase project dashboard
-- 2. Click "SQL Editor" in the left sidebar
-- 3. Click "New query"
-- 4. Paste this entire file
-- 5. Click "Run"
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- STUDENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS students (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID,  -- Required for multi-org filtering
    name TEXT NOT NULL,
    chinese_name TEXT,
    avatar_color TEXT NOT NULL DEFAULT 'blue',
    attendance_status TEXT NOT NULL DEFAULT 'present',
    category_id UUID,
    coach_id UUID,
    program_id UUID,
    birthdate TIMESTAMPTZ,
    profile_image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- PLAYERS TABLE (Extended student info)
-- ============================================
CREATE TABLE IF NOT EXISTS players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID,  -- Required for multi-org filtering
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    height_cm DOUBLE PRECISION,
    weight_kg DOUBLE PRECISION,
    wingspan_cm DOUBLE PRECISION,
    handedness TEXT NOT NULL DEFAULT 'right',
    position TEXT,
    jersey_number INTEGER,
    parent_info JSONB NOT NULL DEFAULT '{}',
    secondary_parent_info JSONB,
    contract_info JSONB NOT NULL DEFAULT '{}',
    skills JSONB NOT NULL DEFAULT '{}',
    coach_notes TEXT,
    medical_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- CONTRACTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS contracts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID,  -- Required for multi-org filtering
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    contract_number INTEGER NOT NULL DEFAULT 1,
    contract_type TEXT,  -- e.g., 'Pay As You Go', '1x Week / 6 Months', etc.
    total_sessions INTEGER NOT NULL DEFAULT 24,
    attended_sessions INTEGER NOT NULL DEFAULT 0,
    weekly_attendance_json TEXT,  -- JSON string of weekly attendance records
    start_date TIMESTAMPTZ,
    expiry_date TIMESTAMPTZ,
    price_per_session DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
    amount_paid DOUBLE PRECISION NOT NULL DEFAULT 0,
    is_signed BOOLEAN NOT NULL DEFAULT FALSE,
    signed_date TIMESTAMPTZ,
    jersey_given BOOLEAN NOT NULL DEFAULT FALSE,
    jersey_given_date TIMESTAMPTZ,
    ball_given BOOLEAN NOT NULL DEFAULT FALSE,
    ball_given_date TIMESTAMPTZ,
    jersey_number INTEGER,
    jersey_size TEXT,
    notes TEXT,
    program_assignments_json TEXT,  -- JSON array of program UUIDs for session assignments
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- PROGRAMS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS programs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID,  -- Required for multi-org filtering
    name TEXT NOT NULL,
    age_group TEXT NOT NULL DEFAULT 'u12',
    duration_weeks INTEGER NOT NULL DEFAULT 12,
    description TEXT,
    objectives TEXT[] NOT NULL DEFAULT '{}',
    enrolled_student_ids UUID[] NOT NULL DEFAULT '{}',
    coach_id UUID,
    status TEXT NOT NULL DEFAULT 'draft',
    color_hex TEXT NOT NULL DEFAULT '#3B82F6',
    mascot TEXT NOT NULL DEFAULT 'Eagles',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    stars INTEGER DEFAULT 1,  -- Quality/tier rating (1-4 stars)
    skill_targets_json TEXT,  -- ProgramSkillTargets as JSON
    recurring_days_json TEXT,  -- [Weekday] as JSON array of ints
    default_session_time TIMESTAMPTZ,
    default_session_duration_minutes INTEGER DEFAULT 90,
    location_id UUID,
    location_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- MICRO CYCLES (Phases) TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS micro_cycles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_id UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL DEFAULT 1,
    title TEXT NOT NULL,
    focus TEXT[] NOT NULL DEFAULT '{}',
    duration_weeks INTEGER NOT NULL DEFAULT 4,
    intensity TEXT NOT NULL DEFAULT 'moderate',
    description TEXT,
    objectives TEXT[] NOT NULL DEFAULT '{}',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- SESSION EVENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS session_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_id UUID REFERENCES programs(id) ON DELETE SET NULL,
    micro_cycle_id UUID REFERENCES micro_cycles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    session_type TEXT NOT NULL DEFAULT 'training',
    date TIMESTAMPTZ NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    location TEXT,
    status TEXT NOT NULL DEFAULT 'scheduled',
    curriculum JSONB NOT NULL DEFAULT '{"warmupDrillIds":[],"skillDrillIds":[],"gameDrillIds":[],"warmupMinutes":10,"skillsMinutes":35,"gameMinutes":15}',
    attendee_ids UUID[] NOT NULL DEFAULT '{}',
    actual_attendee_ids UUID[] NOT NULL DEFAULT '{}',
    notes TEXT,
    coach_notes TEXT,
    man_of_the_match_id UUID,
    drills_completed UUID[] NOT NULL DEFAULT '{}',
    rating INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- MEASUREMENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS measurements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id UUID REFERENCES session_events(id) ON DELETE SET NULL,
    measurement_type TEXT NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    notes TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recorded_by TEXT
);

-- ============================================
-- DRILLS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS drills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'warmup',
    difficulty TEXT NOT NULL DEFAULT 'beginner',
    duration_minutes INTEGER NOT NULL DEFAULT 10,
    equipment_needed TEXT[] NOT NULL DEFAULT '{}',
    instructions TEXT[] NOT NULL DEFAULT '{}',
    key_points TEXT[] NOT NULL DEFAULT '{}',
    variations TEXT[] NOT NULL DEFAULT '{}',
    min_players INTEGER NOT NULL DEFAULT 1,
    max_players INTEGER,
    video_url TEXT,
    tags TEXT[] NOT NULL DEFAULT '{}',
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEXES for better query performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_students_program ON students(program_id);
CREATE INDEX IF NOT EXISTS idx_players_student ON players(student_id);
CREATE INDEX IF NOT EXISTS idx_contracts_student ON contracts(student_id);
CREATE INDEX IF NOT EXISTS idx_micro_cycles_program ON micro_cycles(program_id);
CREATE INDEX IF NOT EXISTS idx_session_events_program ON session_events(program_id);
CREATE INDEX IF NOT EXISTS idx_session_events_micro_cycle ON session_events(micro_cycle_id);
CREATE INDEX IF NOT EXISTS idx_session_events_date ON session_events(date);
CREATE INDEX IF NOT EXISTS idx_measurements_student ON measurements(student_id);

-- ============================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to all tables
DROP TRIGGER IF EXISTS update_students_updated_at ON students;
CREATE TRIGGER update_students_updated_at BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_players_updated_at ON players;
CREATE TRIGGER update_players_updated_at BEFORE UPDATE ON players
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_contracts_updated_at ON contracts;
CREATE TRIGGER update_contracts_updated_at BEFORE UPDATE ON contracts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_programs_updated_at ON programs;
CREATE TRIGGER update_programs_updated_at BEFORE UPDATE ON programs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_micro_cycles_updated_at ON micro_cycles;
CREATE TRIGGER update_micro_cycles_updated_at BEFORE UPDATE ON micro_cycles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_session_events_updated_at ON session_events;
CREATE TRIGGER update_session_events_updated_at BEFORE UPDATE ON session_events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_drills_updated_at ON drills;
CREATE TRIGGER update_drills_updated_at BEFORE UPDATE ON drills
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ============================================
-- STAFF COACHES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS staff_coaches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'assistant',
    specializations TEXT[] DEFAULT '{}',
    age_groups TEXT[] DEFAULT '{}',
    avatar_color TEXT NOT NULL DEFAULT 'blue',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- LOCATIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    city TEXT,
    court_count INTEGER NOT NULL DEFAULT 1,
    court_type TEXT NOT NULL DEFAULT 'indoor',
    amenities TEXT[] DEFAULT '{}',
    capacity INTEGER,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- PLAYS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS plays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'setPlays',
    formation TEXT NOT NULL DEFAULT '',
    play_description TEXT NOT NULL DEFAULT '',
    key_teaching_points TEXT[] DEFAULT '{}',
    steps JSONB DEFAULT '[]',
    variations TEXT[] DEFAULT '{}',
    best_used_against TEXT,
    difficulty TEXT NOT NULL DEFAULT 'intermediate',
    diagram_url TEXT,
    tags TEXT[] DEFAULT '{}',
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Triggers for updated_at
CREATE TRIGGER update_staff_coaches_updated_at BEFORE UPDATE ON staff_coaches FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_locations_updated_at BEFORE UPDATE ON locations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_plays_updated_at BEFORE UPDATE ON plays FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- TEAMS TABLE (League)
-- ============================================
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    color_hex TEXT NOT NULL DEFAULT '#E94560',
    secondary_color_hex TEXT NOT NULL DEFAULT '#1A1A2E',
    logo_system_image TEXT NOT NULL DEFAULT 'basketball.fill',
    mascot_type_raw TEXT,
    player_ids UUID[] DEFAULT '{}',
    coach_name TEXT,
    home_venue TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- GAMES TABLE (League)
-- ============================================
CREATE TABLE IF NOT EXISTS games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    home_team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    away_team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    home_score INTEGER NOT NULL DEFAULT 0,
    away_score INTEGER NOT NULL DEFAULT 0,
    date TIMESTAMPTZ NOT NULL,
    venue TEXT,
    status TEXT NOT NULL DEFAULT 'Scheduled',
    quarter INTEGER,
    time_remaining TEXT,
    notes TEXT,
    player_stats JSONB DEFAULT '[]',
    scoring_plays JSONB DEFAULT '[]',
    quarter_scores JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- TEAM STANDINGS TABLE (League)
-- ============================================
CREATE TABLE IF NOT EXISTS team_standings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    wins INTEGER NOT NULL DEFAULT 0,
    losses INTEGER NOT NULL DEFAULT 0,
    points_for INTEGER NOT NULL DEFAULT 0,
    points_against INTEGER NOT NULL DEFAULT 0,
    streak INTEGER NOT NULL DEFAULT 0,
    last_five_results BOOLEAN[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Triggers for League tables
CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON teams FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_games_updated_at BEFORE UPDATE ON games FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_team_standings_updated_at BEFORE UPDATE ON team_standings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ROW LEVEL SECURITY (RLS) - Disabled for development
-- ============================================
-- RLS is disabled by default, which allows full access via the anon key
-- The tables are accessible without needing policies
-- 
-- To enable RLS in production:
-- 1. Uncomment the ALTER TABLE lines below
-- 2. Create appropriate policies for your auth setup
--
-- ALTER TABLE students ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE players ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE micro_cycles ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE session_events ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE measurements ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE drills ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE staff_coaches ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE plays ENABLE ROW LEVEL SECURITY;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================
SELECT 'SAM database schema created successfully!' as message;
