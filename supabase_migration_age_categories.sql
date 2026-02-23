-- Migration: Add age_categories table for custom category icons and mascot names
-- Run this in Supabase SQL Editor

-- Create age_categories table
CREATE TABLE IF NOT EXISTS age_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    min_age INTEGER NOT NULL DEFAULT 5,
    max_age INTEGER NOT NULL DEFAULT 7,
    color_hex TEXT NOT NULL DEFAULT '#5B8DEF',
    ball_size TEXT NOT NULL DEFAULT 'size5',
    rim_height TEXT NOT NULL DEFAULT 'feet10',
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    custom_icon_base64 TEXT,  -- Base64 encoded image data for custom icons
    mascot_name_override TEXT,  -- Optional override for mascot name
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index for organization lookup
CREATE INDEX IF NOT EXISTS idx_age_categories_organization_id ON age_categories(organization_id);

-- Create index for short_name lookup
CREATE INDEX IF NOT EXISTS idx_age_categories_short_name ON age_categories(short_name);

-- Enable RLS
ALTER TABLE age_categories ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see categories for their organization
CREATE POLICY "Users can view own organization age_categories"
    ON age_categories FOR SELECT
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
    ));

-- RLS Policy: Users can insert categories for their organization
CREATE POLICY "Users can insert own organization age_categories"
    ON age_categories FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
    ));

-- RLS Policy: Users can update categories for their organization
CREATE POLICY "Users can update own organization age_categories"
    ON age_categories FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
    ));

-- RLS Policy: Users can delete categories for their organization
CREATE POLICY "Users can delete own organization age_categories"
    ON age_categories FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
    ));

-- Add updated_at trigger
CREATE OR REPLACE FUNCTION update_age_categories_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_age_categories_updated_at
    BEFORE UPDATE ON age_categories
    FOR EACH ROW
    EXECUTE FUNCTION update_age_categories_updated_at();

-- Grant permissions
GRANT ALL ON age_categories TO authenticated;
GRANT ALL ON age_categories TO service_role;
