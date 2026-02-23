-- Supabase Migration: Event-Based Session Consumption
-- This migration adds fields to support deriving contract session consumption from SessionEvent attendance records
-- Run this migration BEFORE deploying the updated app code

-- ============================================
-- 1. Add historical_sessions_consumed to contracts table
-- ============================================
-- This field stores sessions consumed before event-based tracking began
-- Existing contracts will have their current attended_sessions value migrated here

ALTER TABLE contracts 
ADD COLUMN IF NOT EXISTS historical_sessions_consumed INT DEFAULT 0;

-- Migrate existing data: preserve current counts as historical baseline
-- This ensures existing contracts don't lose their session counts
UPDATE contracts 
SET historical_sessions_consumed = attended_sessions 
WHERE historical_sessions_consumed = 0 AND attended_sessions > 0;

-- ============================================
-- 2. Add excused_absences to session_events table
-- ============================================
-- This array stores student IDs who notified absence in advance (session preserved)
-- Students in this array won't have their session consumed when the session completes

ALTER TABLE session_events 
ADD COLUMN IF NOT EXISTS excused_absences UUID[] DEFAULT '{}';

-- ============================================
-- 3. Create index for efficient contract-session lookup
-- ============================================
-- Helps speed up the sessionsConsumed calculation which filters by program_id and status

CREATE INDEX IF NOT EXISTS idx_session_events_program_status 
ON session_events(program_id, status) 
WHERE status = 'completed';

-- ============================================
-- 4. Verification queries (run these to verify migration success)
-- ============================================

-- Check contracts with historical data migrated
-- SELECT id, student_id, attended_sessions, historical_sessions_consumed 
-- FROM contracts 
-- WHERE historical_sessions_consumed > 0 
-- LIMIT 10;

-- Check session_events table structure
-- SELECT column_name, data_type, column_default 
-- FROM information_schema.columns 
-- WHERE table_name = 'session_events' AND column_name = 'excused_absences';

-- Check contracts table structure
-- SELECT column_name, data_type, column_default 
-- FROM information_schema.columns 
-- WHERE table_name = 'contracts' AND column_name = 'historical_sessions_consumed';

-- ============================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================
-- To rollback this migration, run:
--
-- ALTER TABLE contracts DROP COLUMN IF EXISTS historical_sessions_consumed;
-- ALTER TABLE session_events DROP COLUMN IF EXISTS excused_absences;
-- DROP INDEX IF EXISTS idx_session_events_program_status;

-- ============================================
-- NOTES
-- ============================================
-- 1. The attended_sessions field in contracts is now DEPRECATED but NOT deleted
--    - It remains for backward compatibility with older app versions
--    - New session consumption is calculated from: historical_sessions_consumed + count(matching SessionEvents)
--
-- 2. Session consumption logic (in app):
--    A session is consumed if student:
--    - Attended (in actual_attendee_ids) OR
--    - Was expected but absent and NOT excused (in attendee_ids but not in actual_attendee_ids and not in excused_absences)
--
-- 3. Excused absences preserve the session:
--    - Student must notify in advance
--    - Session is NOT consumed for the student
--    - Useful for illness, family events, etc.
