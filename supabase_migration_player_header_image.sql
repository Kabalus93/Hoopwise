-- Migration: Add header_image_url column to players table
-- Date: 2026-02-13
-- Description: Stores the background image URL for the baseball card-style profile view

-- Add header_image_url column to players table
ALTER TABLE players ADD COLUMN IF NOT EXISTS header_image_url TEXT;

-- Add comment for documentation
COMMENT ON COLUMN players.header_image_url IS 'Background image URL for the baseball card-style profile view';
