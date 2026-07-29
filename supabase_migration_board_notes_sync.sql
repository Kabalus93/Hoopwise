-- Migration: add board_notes_json to session_events for cross-device notes sync
-- Run this in the Supabase SQL editor

ALTER TABLE session_events
ADD COLUMN IF NOT EXISTS board_notes_json TEXT DEFAULT NULL;
