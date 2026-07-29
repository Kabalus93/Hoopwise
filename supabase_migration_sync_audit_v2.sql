-- Migration: Sync Audit V2 — grade_history_json on students, organization_id on reminders
-- Run this against your Supabase project SQL editor

-- 1. Add grade_history_json column to students table
ALTER TABLE students
ADD COLUMN IF NOT EXISTS grade_history_json TEXT;

-- 2. Add organization_id column to reminders table (for multi-org scoping)
ALTER TABLE reminders
ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);

-- 3. Backfill organization_id on existing reminders from the coach's organization
UPDATE reminders r
SET organization_id = sc.organization_id
FROM staff_coaches sc
WHERE r.coach_id = sc.id
  AND r.organization_id IS NULL;

-- 4. Create index on reminders.organization_id for efficient org-scoped queries
CREATE INDEX IF NOT EXISTS idx_reminders_organization_id ON reminders(organization_id);

-- 5. Create index on reminders.updated_at for polling change detection
CREATE INDEX IF NOT EXISTS idx_reminders_updated_at ON reminders(updated_at);

-- 6. Enable RLS policy for reminders scoped to organization (if not already set)
-- Note: Adjust these policies based on your existing RLS setup
-- ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Users can access reminders in their organization"
--   ON reminders FOR ALL
--   USING (organization_id IN (SELECT id FROM organizations WHERE ...));
