-- ============================================
-- SAM Migration: Add Age/Grade Input Fields to Students
-- ============================================
-- Run this SQL in your Supabase SQL Editor to add the new columns
-- 
-- These columns support two age input modes:
-- 1. Date of Birth: birthMonth + birthYear (with optional day via birthdate)
-- 2. School Grade: schoolGrade (K1-K3, P1-P6, H1-H6)
-- ============================================

-- Add birth_month column (1-12 for month selection)
ALTER TABLE students 
ADD COLUMN IF NOT EXISTS birth_month INTEGER;

-- Add birth_year column (year component for month/year input)
ALTER TABLE students 
ADD COLUMN IF NOT EXISTS birth_year INTEGER;

-- Add school_grade column (alternative to birthdate for age estimation)
-- Values: K1, K2, K3, P1, P2, P3, P4, P5, P6, H1, H2, H3, H4, H5, H6
ALTER TABLE students 
ADD COLUMN IF NOT EXISTS school_grade TEXT;

-- Add check constraint for valid school grades
ALTER TABLE students 
ADD CONSTRAINT valid_school_grade 
CHECK (school_grade IS NULL OR school_grade IN (
    'K1', 'K2', 'K3',
    'P1', 'P2', 'P3', 'P4', 'P5', 'P6',
    'H1', 'H2', 'H3', 'H4', 'H5', 'H6'
));

-- Add check constraint for valid birth_month (1-12)
ALTER TABLE students 
ADD CONSTRAINT valid_birth_month 
CHECK (birth_month IS NULL OR (birth_month >= 1 AND birth_month <= 12));

-- Add check constraint for valid birth_year (reasonable range)
ALTER TABLE students 
ADD CONSTRAINT valid_birth_year 
CHECK (birth_year IS NULL OR (birth_year >= 1990 AND birth_year <= 2030));

-- Create index for school_grade queries
CREATE INDEX IF NOT EXISTS idx_students_school_grade ON students(school_grade);

-- Create index for birth_year queries (useful for age-based filtering)
CREATE INDEX IF NOT EXISTS idx_students_birth_year ON students(birth_year);

-- ============================================
-- Verification Query (optional)
-- ============================================
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_name = 'students' 
-- AND column_name IN ('birth_month', 'birth_year', 'school_grade');
