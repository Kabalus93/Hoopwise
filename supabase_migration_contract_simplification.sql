-- Migration: Simplify contracts with enrollment tracking and session attendance
-- Date: 2026-02-13
-- Description: Adds enrollment_date and attended_session_ids_json columns to contracts table
--              for simplified contract tracking per user request

-- Add enrollment_date column to contracts table
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS enrollment_date TIMESTAMPTZ;

-- Add attended_session_ids_json column to contracts table
-- Stores array of session event UUIDs that the student attended as JSON
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS attended_session_ids_json TEXT;

-- Backfill enrollment_date from start_date for existing contracts
UPDATE contracts SET enrollment_date = start_date WHERE enrollment_date IS NULL AND start_date IS NOT NULL;

-- For contracts without start_date, use created_at
UPDATE contracts SET enrollment_date = created_at WHERE enrollment_date IS NULL;

-- Add comments for documentation
COMMENT ON COLUMN contracts.enrollment_date IS 'When the student enrolled in this contract';
COMMENT ON COLUMN contracts.attended_session_ids_json IS 'JSON array of session event UUIDs that the student attended';
