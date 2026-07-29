-- Supabase Migration: Media Assets Fields
-- This migration adds the media_assets_json column to students table
-- to store photo/video URLs and metadata for the Media Vault feature.
-- Run this migration BEFORE deploying the updated app code.

-- ============================================
-- 1. Add media_assets_json to students table
-- ============================================
-- Stores media assets as JSON object with photoUrls, videoUrls, dates, etc.
-- Structure: {
--   "photoReady": bool,
--   "videoHighlightPending": bool,
--   "lastPhotoDate": ISO8601 string,
--   "lastVideoDate": ISO8601 string,
--   "notes": string,
--   "photoUrls": ["url1", "url2", ...],
--   "videoUrls": ["url1", "url2", ...]
-- }

ALTER TABLE students
ADD COLUMN IF NOT EXISTS media_assets_json TEXT DEFAULT NULL;

-- ============================================
-- 2. Add personal_bests_json to students table
-- ============================================
-- Stores personal bests as JSON object (e.g., {"ppg": 15.2, "3pt%": 0.42})

ALTER TABLE students
ADD COLUMN IF NOT EXISTS personal_bests_json TEXT DEFAULT NULL;

-- ============================================
-- 3. Verification queries
-- ============================================

-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'students'
--   AND column_name IN ('media_assets_json', 'personal_bests_json');

-- ============================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================
-- ALTER TABLE students DROP COLUMN IF EXISTS media_assets_json;
-- ALTER TABLE students DROP COLUMN IF EXISTS personal_bests_json;
