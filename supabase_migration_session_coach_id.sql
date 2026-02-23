-- Migration: Add created_by_coach_id to session_events table
-- Run this in your Supabase SQL Editor

-- Add the created_by_coach_id column to session_events
ALTER TABLE session_events 
ADD COLUMN IF NOT EXISTS created_by_coach_id UUID REFERENCES staff_coaches(id) ON DELETE SET NULL;

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_session_events_created_by_coach_id 
ON session_events(created_by_coach_id);

-- Verify the column was added
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'session_events' AND column_name = 'created_by_coach_id';
