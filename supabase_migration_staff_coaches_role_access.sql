-- Migration: Add missing columns to staff_coaches table
-- Fixes persistence of role, access_level, hire_date, and notes fields.
-- Run this in your Supabase SQL editor BEFORE deploying the updated app.

-- ============================================================
-- 1. Add access_level column
-- ============================================================
-- Stores the coach's access level: 'Admin' or 'Coaching Staff'

ALTER TABLE staff_coaches
ADD COLUMN IF NOT EXISTS access_level TEXT NOT NULL DEFAULT 'Coaching Staff';

-- ============================================================
-- 2. Add hire_date column
-- ============================================================

ALTER TABLE staff_coaches
ADD COLUMN IF NOT EXISTS hire_date TIMESTAMPTZ DEFAULT NULL;

-- ============================================================
-- 3. Add notes column
-- ============================================================

ALTER TABLE staff_coaches
ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT NULL;

-- ============================================================
-- 4. Backfill access_level for any existing rows that have NULL
--    (shouldn't happen due to DEFAULT, but just in case)
-- ============================================================

UPDATE staff_coaches
SET access_level = 'Coaching Staff'
WHERE access_level IS NULL;

-- ============================================================
-- 5. Verification queries (uncomment to check)
-- ============================================================

-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'staff_coaches'
--   AND column_name IN ('access_level', 'hire_date', 'notes', 'role');

-- ============================================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================================
-- ALTER TABLE staff_coaches DROP COLUMN IF EXISTS access_level;
-- ALTER TABLE staff_coaches DROP COLUMN IF EXISTS hire_date;
-- ALTER TABLE staff_coaches DROP COLUMN IF EXISTS notes;
