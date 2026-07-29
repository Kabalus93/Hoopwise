-- Profile Audit Log
-- Tracks who modified a student profile, when, and what changed.
-- Entries are kept for 30 days; the app filters client-side as well.

create table if not exists profile_audit_log (
    id           uuid primary key default gen_random_uuid(),
    student_id   uuid not null,
    coach_id     uuid not null,
    coach_name   text not null,
    field        text not null,
    summary      text not null,
    changed_at   timestamptz not null default now()
);

-- Fast lookup: most recent entries for a student
create index if not exists idx_profile_audit_student_time
    on profile_audit_log (student_id, changed_at desc);

-- Row-level security: org members can read; coaches can insert their own rows
alter table profile_audit_log enable row level security;

create policy "Org members can read audit log"
    on profile_audit_log for select
    using (
        exists (
            select 1 from staff_coaches sc
            where sc.id = auth.uid()
              and sc.organization_id = (
                  select organization_id from students s where s.id = student_id limit 1
              )
        )
    );

create policy "Coaches can insert own audit entries"
    on profile_audit_log for insert
    with check (coach_id = auth.uid());

-- Auto-purge entries older than 30 days (optional: run via pg_cron or Supabase scheduled function)
-- delete from profile_audit_log where changed_at < now() - interval '30 days';
