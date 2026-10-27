-- Daily Activity Summaries (HKActivitySummary — the "activity rings").
-- Unlike raw samples these have no UUID and one row per local calendar day;
-- the current day mutates as more activity is recorded, so ingest upserts with
-- ON CONFLICT (date) DO UPDATE and an explicit null clears a value. The PK is a
-- plain `date` (not timestamptz): rings are local-calendar days, so storing the
-- local date directly sidesteps timezone drift that would split a day in two.
-- Plain table: at most ~366 rows/year.
--
-- Idempotent (IF NOT EXISTS everywhere): it predates the migrate service and
-- was applied by hand to live databases whose volume predated the file.

CREATE TABLE IF NOT EXISTS activity_summaries (
    date               date        NOT NULL,
    user_id            uuid        NOT NULL REFERENCES users (id)
                                   DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    move_kcal          float8,
    move_goal_kcal     float8,
    exercise_min       float8,
    exercise_goal_min  float8,
    stand_hours        float8,
    stand_goal_hours   float8,
    move_mode          smallint,   -- 0 = activeEnergy, 1 = appleMoveTime
    move_time_min      float8,     -- populated for appleMoveTime-mode users
    move_time_goal_min float8,
    updated_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, date)
);

ALTER TABLE batches ADD COLUMN IF NOT EXISTS activity_summary_count int;
