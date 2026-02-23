-- ============================================
-- SAM Database Migration: Add Missing Columns
-- ============================================
-- Run this SQL in your Supabase SQL Editor to add missing columns
-- This is safe to run multiple times (uses IF NOT EXISTS pattern)
-- ============================================

-- Add organization_id to students
ALTER TABLE students ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id to players
ALTER TABLE players ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id to contracts
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id and new schedule columns to programs
ALTER TABLE programs ADD COLUMN IF NOT EXISTS organization_id UUID;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS skill_targets_json TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS recurring_days_json TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS default_session_time TIMESTAMPTZ;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS default_session_duration_minutes INTEGER DEFAULT 90;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS location_id UUID;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS location_name TEXT;

-- Add organization_id to micro_cycles
ALTER TABLE micro_cycles ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id to session_events
ALTER TABLE session_events ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id to drills
ALTER TABLE drills ADD COLUMN IF NOT EXISTS organization_id UUID;

-- Add organization_id to measurements
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS organization_id UUID;

-- ============================================
-- UPDATE EXISTING RECORDS WITH ORGANIZATION ID
-- ============================================
-- First, find your organization ID:
-- SELECT id, display_name FROM organizations;

-- Then uncomment and run these updates with your actual organization UUID:
-- UPDATE students SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE players SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE contracts SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE programs SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE micro_cycles SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE session_events SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE drills SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;
-- UPDATE measurements SET organization_id = 'YOUR_ORG_UUID' WHERE organization_id IS NULL;

SELECT 'Migration completed successfully! Now update existing records with your organization_id.' as message;
