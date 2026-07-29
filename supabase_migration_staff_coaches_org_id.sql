-- Migration: Add organization_id to staff_coaches table
-- Run this in your Supabase SQL editor

-- 1. Add organization_id column to staff_coaches
ALTER TABLE staff_coaches 
ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id);

-- 2. Create index for faster organization-based queries
CREATE INDEX IF NOT EXISTS idx_staff_coaches_organization_id 
ON staff_coaches(organization_id);

-- 3. Update existing staff coaches to have the correct organization_id
-- First, find coaches that match organization accounts and set their org_id
UPDATE staff_coaches sc
SET organization_id = oa.organization_id
FROM organization_accounts oa
WHERE sc.email = oa.username OR LOWER(sc.email) = LOWER(oa.username)
  AND sc.organization_id IS NULL;

-- 4. For any remaining coaches without org_id, you may need to manually assign them
-- or delete sample data coaches that shouldn't exist in production:
-- DELETE FROM staff_coaches WHERE organization_id IS NULL AND name IN ('Marcus Rivera', 'Aisha Thompson', 'David Park');

-- Note: After running this migration, the app will filter staff coaches by organization_id.
-- Coaches with NULL organization_id will only appear in guest/demo mode.
