-- Hardening of the viewer's accounts mode (015_web_accounts.sql,
-- 016_web_signups.sql), from the October 2026 deep review
-- (docs/deep-review-2026-10.md S7, S8, F2, O13). 016 is applied and so
-- immutable: everything here replaces one of its functions in place, with
-- the same signature, owner and grants, or adds one.
--
--  * auth.session_owner: a session also dies 90 days after sign-in, however
--    often it is used — the absolute cap web/lib/accounts/session.ts
--    (SESSION_ABSOLUTE_DAYS) already enforces on every viewer request.
--    Every definer function checks the caller's session through this one.
--  * auth.set_account_disabled: never an administrator's account, and never
--    the caller's own. /admin hides those buttons; this is the check.
--  * auth.decline_signups: declines (deletes) pending requests in bulk, for
--    an administrator's session.
--  * auth.prune_signups (the hourly job): also deletes a request nobody
--    decided within 30 days, and every expired session — expired by its
--    sliding 30 days or by the 90-day cap — which the viewer used to sweep
--    on every sign-in.
--
-- Same rules as 016: every definer function pins search_path to pg_catalog
-- and names its objects in full, and web_app may EXECUTE exactly the set
-- 099_read_roles.sh grants and asserts (auth.decline_signups added there).

-- ── session check ───────────────────────────────────────────────────────────
-- As 016's, plus the absolute lifetime. Keep the 90 days in step with
-- SESSION_ABSOLUTE_DAYS in web/lib/accounts/session.ts and with the sweep in
-- auth.prune_signups below.
CREATE OR REPLACE FUNCTION auth.session_owner(p_session bytea)
RETURNS TABLE (account_id uuid, user_id uuid, is_admin boolean, self_service boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT a.id, a.user_id, a.is_admin,
         EXISTS (SELECT 1 FROM auth.self_service_users ss WHERE ss.user_id = a.user_id)
    FROM auth.sessions s
    JOIN auth.accounts a ON a.id = s.account_id
   WHERE octet_length(p_session) = 32
     AND s.id = p_session
     AND s.expires_at > now()
     AND s.created_at > now() - interval '90 days'
     AND a.disabled_at IS NULL
     AND a.password_hash IS NOT NULL
$$;
REVOKE ALL ON FUNCTION auth.session_owner(bytea) FROM PUBLIC;

-- ── disabling (administrators) ──────────────────────────────────────────────
-- As 016's, with two more refusals. An administrator's account — the
-- caller's own included — is never disabled or enabled here: one
-- administrator could otherwise lock out another, or themselves, through
-- /api/admin, and an administrator the operator disabled by hand could be
-- brought back. Administrators are managed from the server (make
-- web-invite --admin, SQL), like the household. The self-service check
-- comes first, so a household account still reads as not found (P0002).
CREATE OR REPLACE FUNCTION auth.set_account_disabled(p_session bytea, p_account uuid, p_disabled boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller record;
  target record;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.is_admin THEN
    RAISE EXCEPTION 'only an administrator may disable accounts' USING ERRCODE = '42501';
  END IF;
  SELECT a.id, a.user_id, a.is_admin, a.deletion_requested_at INTO target FROM auth.accounts a
   WHERE a.id = p_account
     AND EXISTS (SELECT 1 FROM auth.self_service_users ss WHERE ss.user_id = a.user_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no self-service account %', p_account USING ERRCODE = 'P0002';
  END IF;
  IF target.id = caller.account_id THEN
    RAISE EXCEPTION 'an administrator cannot disable or enable their own account here' USING ERRCODE = '42501';
  END IF;
  IF target.is_admin THEN
    RAISE EXCEPTION 'an administrator''s account is managed from the server, not here' USING ERRCODE = '42501';
  END IF;
  IF p_disabled THEN
    UPDATE auth.accounts SET disabled_at = now() WHERE id = p_account AND disabled_at IS NULL;
    DELETE FROM auth.sessions WHERE account_id = p_account;
    UPDATE public.device_tokens SET status = 'revoked', revoked_at = now()
     WHERE user_id = target.user_id AND status = 'active';
  ELSIF target.deletion_requested_at IS NOT NULL THEN
    RAISE EXCEPTION 'this person asked to be deleted; purge instead' USING ERRCODE = '55000';
  ELSE
    UPDATE auth.accounts SET disabled_at = NULL WHERE id = p_account;
  END IF;
END
$$;
REVOKE ALL ON FUNCTION auth.set_account_disabled(bytea, uuid, boolean) FROM PUBLIC;

-- ── declining requests (administrators) ─────────────────────────────────────
-- Deletes the given requests that are still pending (a decided one is left
-- alone) and returns how many went; no email is sent. One request or a
-- page's worth: /admin's Decline, Decline selected and Decline all shown.
-- web_app may delete these rows itself (it writes the account store); the
-- function exists so a decision is checked against an administrator's
-- session in the database, like an approval. At most 1000 at once.
CREATE FUNCTION auth.decline_signups(p_session bytea, p_requests uuid[])
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller record;
  n      integer;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.is_admin THEN
    RAISE EXCEPTION 'only an administrator may decline requests' USING ERRCODE = '42501';
  END IF;
  IF coalesce(cardinality(p_requests), 0) > 1000 THEN
    RAISE EXCEPTION 'decline at most 1000 requests at once' USING ERRCODE = '22023';
  END IF;
  DELETE FROM auth.signup_requests WHERE id = ANY (p_requests) AND status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END
$$;
REVOKE ALL ON FUNCTION auth.decline_signups(bytea, uuid[]) FROM PUBLIC;

-- ── housekeeping ────────────────────────────────────────────────────────────
-- As 016's (still the hourly TimescaleDB job 016 scheduled: replacing the
-- procedure in place keeps the job pointing at it), plus:
--  * a pending request nobody decided is deleted 30 days after it was made,
--    so the privacy policy's 30 days hold for every request, and a flood of
--    requests drains by itself (the viewer also stops taking new ones while
--    500 are pending: web/lib/accounts/signups.ts);
--  * expired sessions — past their sliding expiry, or signed in more than 90
--    days ago (auth.session_owner above) — are deleted. They sign nobody in
--    either way; this keeps the IP address and browser name each one holds
--    no longer than the session lives (give or take this hour).
CREATE OR REPLACE PROCEDURE auth.prune_signups(job_id integer, config jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  u uuid;
BEGIN
  DELETE FROM auth.signup_requests WHERE status <> 'pending' AND decided_at < now() - interval '30 days';
  DELETE FROM auth.signup_requests WHERE status = 'pending' AND created_at < now() - interval '30 days';
  DELETE FROM auth.sessions WHERE expires_at < now() OR created_at < now() - interval '90 days';
  FOR u IN
    SELECT ss.user_id FROM auth.self_service_users ss
     WHERE ss.approved_at < now() - interval '30 days'
       AND NOT EXISTS (SELECT 1 FROM auth.accounts a WHERE a.user_id = ss.user_id)
       AND NOT EXISTS (SELECT 1 FROM auth.invites i WHERE i.user_id = ss.user_id AND i.created_at > now() - interval '30 days')
  LOOP
    BEGIN
      DELETE FROM auth.invites WHERE user_id = u;
      DELETE FROM public.users WHERE id = u;
    EXCEPTION WHEN foreign_key_violation THEN
      RAISE WARNING 'prune_signups: user % still has rows elsewhere; left in place', u;
    END;
  END LOOP;
END
$$;
REVOKE ALL ON PROCEDURE auth.prune_signups(integer, jsonb) FROM PUBLIC;
