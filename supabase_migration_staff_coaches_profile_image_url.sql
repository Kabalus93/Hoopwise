-- Migration: add profile_image_url to staff_coaches
-- Run this in the Supabase SQL editor

ALTER TABLE staff_coaches
ADD COLUMN IF NOT EXISTS profile_image_url TEXT DEFAULT NULL;
