-- Migration: Unify login to use organization_accounts only
-- Run this in your Supabase SQL editor

-- 1. Add email column to organization_accounts for unified login
ALTER TABLE organization_accounts 
ADD COLUMN IF NOT EXISTS email TEXT;

-- 2. Create index on email for fast lookups
CREATE INDEX IF NOT EXISTS idx_organization_accounts_email 
ON organization_accounts(email) WHERE email IS NOT NULL;

-- 3. Remove the foreign key constraint on created_by that references user_accounts
-- (This was causing FK violations since creators are in organization_accounts, not user_accounts)
ALTER TABLE organization_accounts 
DROP CONSTRAINT IF EXISTS organization_accounts_created_by_fkey;

-- 4. Optional: Migrate existing user_accounts to organization_accounts
-- Uncomment and run if you have existing user_accounts you want to migrate:
/*
INSERT INTO organization_accounts (id, organization_id, username, email, password_hash, name, role, is_active, created_at, created_by)
SELECT 
    id,
    organization_id,
    LOWER(REPLACE(email, '@', '_')), -- Convert email to username
    email,
    password_hash,
    name,
    role,
    true,
    created_at,
    NULL
FROM user_accounts
WHERE organization_id IS NOT NULL
ON CONFLICT (id) DO NOTHING;
*/

-- Note: After migration, all logins will use organization_accounts table only.
-- Users can log in with either username or email.
