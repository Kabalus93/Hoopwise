-- Migration: Add attendance_photo_path column to session_events table
-- This stores the local file path to the compressed attendance photo

-- Add the column
ALTER TABLE session_events
ADD COLUMN IF NOT EXISTS attendance_photo_path TEXT;

-- Add comment explaining the column
COMMENT ON COLUMN session_events.attendance_photo_path IS 'Local file path to compressed attendance photo (~200KB). Photos are stored locally only to minimize cloud storage costs.';

-- Create index for querying sessions with photos
CREATE INDEX IF NOT EXISTS idx_session_events_has_photo 
ON session_events (attendance_photo_path) 
WHERE attendance_photo_path IS NOT NULL;

-- Update RLS policies to ensure proper organization filtering
-- (existing policies should already handle this, but verify)

COMMENT ON TABLE session_events IS 'Session events with automatic status transitions and attendance photo tracking. Photos compressed to ~200KB and stored locally.';
