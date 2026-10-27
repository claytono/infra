-- Retention for ingest_rejections (012_ingest_rejections.sql), which nothing
-- ever pruned. A client stuck re-sending a page the server always refuses
-- adds a row on every wake, on the disk that holds the only copy of the
-- data. The rows are for diagnosing recent failures (the Ops dashboard's
-- Recent Rejected Batches panel and the rejection alert rules, which look
-- back hours), so 90 days is ample.
--
-- Daily, as a TimescaleDB job like auth.prune_signups (016_web_signups.sql),
-- so it happens in the database whether or not anyone looks. Owned by the
-- migrating superuser and executable by no other role; search_path pinned
-- and the table named in full, like the functions in 016.
CREATE PROCEDURE public.prune_ingest_rejections(job_id integer, config jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  DELETE FROM public.ingest_rejections WHERE received_at < now() - interval '90 days';
END
$$;
REVOKE ALL ON PROCEDURE public.prune_ingest_rejections(integer, jsonb) FROM PUBLIC;
SELECT add_job('public.prune_ingest_rejections', INTERVAL '1 day', initial_start => now() + INTERVAL '10 minutes');
