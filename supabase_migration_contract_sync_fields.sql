-- Supabase Migration: Contract Sync Fields
-- This migration adds missing columns to the contracts table so that
-- manual_status and created_by_coach_id sync correctly between devices.
-- Run this migration BEFORE deploying the updated app code.

-- ============================================
-- 1. Add manual_status to contracts table
-- ============================================
-- Allows coaches to manually override the computed contract status
-- Values: 'Pending', 'Active', 'Completed', 'Expired', 'Cancelled'

ALTER TABLE contracts
ADD COLUMN IF NOT EXISTS manual_status TEXT DEFAULT NULL;

-- ============================================
-- 2. Add created_by_coach_id to contracts table
-- ============================================
-- Tracks which coach created the contract (for access control)

ALTER TABLE contracts
ADD COLUMN IF NOT EXISTS created_by_coach_id UUID DEFAULT NULL;

-- ============================================
-- 3. Add program_assignments_json to contracts table
-- ============================================
-- Stores program IDs assigned to each session slot as JSON

ALTER TABLE contracts
ADD COLUMN IF NOT EXISTS program_assignments_json TEXT DEFAULT NULL;

-- ============================================
-- 4. Add weekly_attendance_json to contracts table
-- ============================================
-- Stores weekly attendance records as JSON (if not already present)

ALTER TABLE contracts
ADD COLUMN IF NOT EXISTS weekly_attendance_json TEXT DEFAULT NULL;

-- ============================================
-- 5. Verification queries (run these to verify migration success)
-- ============================================

-- Check contracts table has new columns
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'contracts'
--   AND column_name IN ('manual_status', 'created_by_coach_id', 'program_assignments_json', 'weekly_attendance_json');

-- ============================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================
-- To rollback this migration, run:
--
-- ALTER TABLE contracts DROP COLUMN IF EXISTS manual_status;
-- ALTER TABLE contracts DROP COLUMN IF EXISTS created_by_coach_id;
-- ALTER TABLE contracts DROP COLUMN IF EXISTS program_assignments_json;
-- ALTER TABLE contracts DROP COLUMN IF EXISTS weekly_attendance_json;

-- ============================================
-- NOTES
-- ============================================
-- 1. manual_status is nullable - when NULL, the app computes status automatically
--    from contract state (signed, expired, sessions remaining, etc.)
--
-- 2. created_by_coach_id references the coach UUID who created the contract.
--    Used for access control in multi-coach organizations.
--
-- 3. program_assignments_json stores a JSON array of program UUIDs,
--    one per session slot. Used to link contracts to specific programs.
--
-- 4. weekly_attendance_json stores a JSON array of WeeklyAttendanceRecord objects.
--    Each record tracks expected vs attended sessions per week.
