-- Migration to fix schema mismatches causing sync errors
-- Run this in Supabase SQL Editor: https://mgovivfcudovnejyiaau.supabase.co

-- ============================================
-- 1. Add missing 'games' column to session_events
-- ============================================
-- This stores in-session scrimmage games with teams and player stats
ALTER TABLE session_events 
ADD COLUMN IF NOT EXISTS games JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN session_events.games IS 'Array of SessionGame objects for in-session scrimmages';

-- ============================================
-- 2. Add missing 'stats' column to programs (if needed)
-- ============================================
-- Note: Check if this column is actually needed or if it's a typo in logs
-- The SupabaseProgram DTO doesn't have a 'stats' field, so this might be from old code
-- Uncomment if you actually need this column:
-- ALTER TABLE programs 
-- ADD COLUMN IF NOT EXISTS stats JSONB DEFAULT '{}'::jsonb;

-- ============================================
-- 3. Ensure all required columns exist in measurements
-- ============================================
-- Verify measurements table has all required columns
DO $$
BEGIN
    -- Check if recordedBy column exists, add if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'measurements' AND column_name = 'recordedby'
    ) THEN
        ALTER TABLE measurements ADD COLUMN recordedBy TEXT;
    END IF;
END $$;

-- ============================================
-- 4. Update existing session_events to have empty games array
-- ============================================
UPDATE session_events 
SET games = '[]'::jsonb 
WHERE games IS NULL;

-- ============================================
-- 5. Create indexes for better query performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_session_events_games ON session_events USING GIN (games);

-- ============================================
-- 6. Verify schema changes
-- ============================================
-- Run this to verify the changes:
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'session_events' 
  AND column_name = 'games';

-- Expected output:
-- column_name | data_type | is_nullable | column_default
-- games       | jsonb     | YES         | '[]'::jsonb
