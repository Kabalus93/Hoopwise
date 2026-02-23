-- ============================================
-- Add missing 'stars' column to programs table
-- ============================================
-- This migration adds the stars column that was missing from the original schema
-- Run this in Supabase SQL Editor

-- Add stars column to programs table
ALTER TABLE programs 
ADD COLUMN IF NOT EXISTS stars INTEGER DEFAULT 1;

-- Add comment for documentation
COMMENT ON COLUMN programs.stars IS 'Quality/tier rating (1-4 stars) for program difficulty/prestige';

-- Verify the column was added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'programs' 
AND column_name = 'stars';
