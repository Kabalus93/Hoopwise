-- Supabase Migration: Student Sync Fields
-- This migration adds missing columns to the students table so that
-- created_by_coach_id, parental touchpoints, and last parent contact
-- sync correctly between devices.
-- Run this migration BEFORE deploying the updated app code.

-- ============================================
-- 1. Add created_by_coach_id to students table
-- ============================================
-- Tracks which coach created the student record (for access control)

ALTER TABLE students
ADD COLUMN IF NOT EXISTS created_by_coach_id UUID DEFAULT NULL;

-- ============================================
-- 2. Add parental_touchpoints_json to students table
-- ============================================
-- Stores parental engagement touchpoints as JSON array

ALTER TABLE students
ADD COLUMN IF NOT EXISTS parental_touchpoints_json TEXT DEFAULT NULL;

-- ============================================
-- 3. Add last_parent_contact to students table
-- ============================================
-- Tracks last parent contact date for engagement monitoring

ALTER TABLE students
ADD COLUMN IF NOT EXISTS last_parent_contact TIMESTAMPTZ DEFAULT NULL;

-- ============================================
-- 4. Add chinese_name column for staff_coaches table
-- ============================================
-- Stores Chinese name for staff coaches (was previously skipped in encoder)

ALTER TABLE staff_coaches
ADD COLUMN IF NOT EXISTS chinese_name TEXT DEFAULT NULL;

-- ============================================
-- 5. Verification queries
-- ============================================

-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'students'
--   AND column_name IN ('created_by_coach_id', 'parental_touchpoints_json', 'last_parent_contact');

-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'staff_coaches'
--   AND column_name = 'chinese_name';

-- ============================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================
-- ALTER TABLE students DROP COLUMN IF EXISTS created_by_coach_id;
-- ALTER TABLE students DROP COLUMN IF EXISTS parental_touchpoints_json;
-- ALTER TABLE students DROP COLUMN IF EXISTS last_parent_contact;
-- ALTER TABLE staff_coaches DROP COLUMN IF EXISTS chinese_name;
