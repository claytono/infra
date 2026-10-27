-- Sign-up requests, and the few privileged steps the viewer's accounts mode
-- needs beyond reading one person's records (015_web_accounts.sql).
--
-- Anyone may ask for an account (/signup); nothing exists for them until an
-- administrator approves it on /admin. Approval creates the user, the
-- viewer then emails an invite, and only a signed-in person can connect
-- their own iPhone. So no data can arrive for anyone the operator has not
-- accepted: before approval there is no user, no account and no sync token.
--
-- Those steps write where web_app has no grant — `users`, `device_tokens`,
-- and (for a deletion) every table holding health data — so each is a
-- SECURITY DEFINER function owned by the migrating superuser, and web_app
-- may EXECUTE exactly these (099_read_roles.sh grants and asserts it).
--
-- The boundary that holds even against a compromised viewer: **these
-- functions act only on users an approved sign-up created**, recorded in
-- auth.self_service_users, which web_app can read but never write. The
-- operator's own household (users that arrived any other way: the seeded
-- default user, `make issue-device`, `make web-invite`) cannot be given a
-- token, disabled, deleted or purged through the viewer at all — only read,
-- as before. Each function also takes the caller's session (its SHA-256, as
-- auth.sessions stores it) and acts for that account; that scopes normal use
-- to the signed-in person, but it is not a barrier against SQL run as
-- web_app, which writes auth.sessions itself to sign people in.
--
-- Every definer function pins search_path to pg_catalog and names its
-- objects in full, so nothing a caller creates can stand in for them.

-- ── requests ────────────────────────────────────────────────────────────────
CREATE TABLE auth.signup_requests (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    email       text        NOT NULL CHECK (email = lower(btrim(email)) AND email <> ''),
    name        text        NOT NULL DEFAULT '' CHECK (char_length(name) <= 200),
    note        text        NOT NULL DEFAULT '' CHECK (char_length(note) <= 2000),
    status      text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    -- Shown to the administrator deciding; not used for anything else.
    ip          inet,
    user_agent  text,
    decided_at  timestamptz,
    decided_by  uuid        REFERENCES auth.accounts (id) ON DELETE SET NULL,
    -- The user an approval created.
    user_id     uuid        REFERENCES users (id) ON DELETE SET NULL
);
-- One open request per address: asking twice does not queue twice.
CREATE UNIQUE INDEX signup_requests_pending_email ON auth.signup_requests (email) WHERE status = 'pending';
CREATE INDEX signup_requests_created_idx ON auth.signup_requests (created_at DESC);

-- Set when a person deletes their own account: it is disabled at once, its
-- sync tokens revoked, and its data waits for an administrator to purge it.
ALTER TABLE auth.accounts ADD COLUMN deletion_requested_at timestamptz;

-- ── who the viewer may act on ──────────────────────────────────────────────
-- Users created by an approved sign-up. Written only by approve_signup;
-- web_app may read it (the account page asks whether to offer
-- self-service), never write it.
CREATE TABLE auth.self_service_users (
    user_id     uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    request_id  uuid,
    approved_at timestamptz NOT NULL DEFAULT now()
);

-- ── session check ───────────────────────────────────────────────────────────
-- The live, enabled account a session belongs to (by the SHA-256 that
-- auth.sessions stores; the plaintext never reaches the database), and
-- whether its user is self-service. Not granted to anyone: the definer
-- functions below call it.
CREATE FUNCTION auth.session_owner(p_session bytea)
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
     AND a.disabled_at IS NULL
     AND a.password_hash IS NOT NULL
$$;
REVOKE ALL ON FUNCTION auth.session_owner(bytea) FROM PUBLIC;

-- ── approval (administrators) ───────────────────────────────────────────────
-- Approves a pending request: makes the person's user — or reuses the one an
-- earlier approval of the same address made, if its invite was never used —
-- marks it self-service, and records who decided. The viewer then writes the
-- invite (auth.invites) in the same transaction and emails it.
CREATE FUNCTION auth.approve_signup(p_session bytea, p_request uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller   record;
  req      record;
  the_user uuid;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.is_admin THEN
    RAISE EXCEPTION 'only an administrator may approve requests' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO req FROM auth.signup_requests WHERE id = p_request FOR UPDATE;
  IF NOT FOUND OR req.status <> 'pending' THEN
    RAISE EXCEPTION 'no pending request %', p_request USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.accounts WHERE email = req.email) THEN
    RAISE EXCEPTION 'an account already signs in with that address' USING ERRCODE = '23505';
  END IF;
  SELECT r.user_id INTO the_user
    FROM auth.signup_requests r
    JOIN auth.self_service_users ss ON ss.user_id = r.user_id
   WHERE r.email = req.email AND r.status = 'approved'
     AND NOT EXISTS (SELECT 1 FROM auth.accounts a WHERE a.user_id = r.user_id)
   ORDER BY r.decided_at DESC
   LIMIT 1;
  IF the_user IS NULL THEN
    the_user := gen_random_uuid();
    INSERT INTO public.users (id) VALUES (the_user);
    INSERT INTO auth.self_service_users (user_id, request_id) VALUES (the_user, p_request);
  END IF;
  UPDATE auth.signup_requests
     SET status = 'approved', user_id = the_user, decided_at = now(), decided_by = caller.account_id
   WHERE id = p_request;
  RETURN the_user;
END
$$;
REVOKE ALL ON FUNCTION auth.approve_signup(bytea, uuid) FROM PUBLIC;

-- Disables a self-service account (it cannot sign in, its sessions end and
-- every sync token of its user is revoked, so its phone stops uploading) or
-- enables it again (tokens stay revoked: the person reconnects). An account
-- whose owner asked to be deleted cannot be enabled: the request stands
-- until the data is purged.
CREATE FUNCTION auth.set_account_disabled(p_session bytea, p_account uuid, p_disabled boolean)
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
  SELECT a.id, a.user_id, a.deletion_requested_at INTO target FROM auth.accounts a
   WHERE a.id = p_account
     AND EXISTS (SELECT 1 FROM auth.self_service_users ss WHERE ss.user_id = a.user_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no self-service account %', p_account USING ERRCODE = 'P0002';
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

-- Deletes everything stored for a self-service user whose account is
-- disabled (or who never made one): health data in every table, the rows
-- the quantity_rollups continuous aggregate made from it, sync tokens and
-- batches, the account, its requests and invites, and the user row; the
-- names of devices and apps no one else's records use are blanked. The
-- deletes on compressed hypertables are narrowed to the user's own
-- segments (types and time span; workouts), so only the batches holding
-- this user's rows are opened — shared with other users of the same type,
-- so this can take minutes on a long history, and the viewer runs it with a
-- long statement timeout. The compression policy packs them up again.
-- Returns the rows removed per table.
CREATE FUNCTION auth.purge_user(p_session bytea, p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller  record;
  counts  jsonb := '{}'::jsonb;
  n       bigint;
  lo      timestamptz;
  hi      timestamptz;
  types   smallint[];
  srcs    smallint[];
  used    smallint[];
  wks     uuid[];
  mat     text;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.is_admin THEN
    RAISE EXCEPTION 'only an administrator may delete data' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.self_service_users WHERE user_id = p_user) THEN
    RAISE EXCEPTION 'not a self-service user: %', p_user USING ERRCODE = '42501';
  END IF;
  -- Lock the user row: every insert that names this user (an account from
  -- an invite, a sync token, a batch) checks its foreign key with a lock
  -- that waits on this one, then fails once the row is gone. NOWAIT, so a
  -- second purge of the same user (an administrator retrying after the page
  -- timed out) fails at once instead of holding a connection while it waits.
  PERFORM 1 FROM public.users WHERE id = p_user FOR UPDATE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no user %', p_user USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.accounts WHERE user_id = p_user AND disabled_at IS NULL) THEN
    RAISE EXCEPTION 'disable the account first' USING ERRCODE = '55000';
  END IF;

  UPDATE public.device_tokens SET status = 'revoked', revoked_at = now()
   WHERE user_id = p_user AND status = 'active';
  -- Same as ingest's InsertBatch: deleting from compressed chunks may
  -- decompress more tuples than the default per-transaction cap.
  PERFORM set_config('timescaledb.max_tuples_decompressed_per_dml_transaction', '0', true);

  SELECT min(start_ts), max(start_ts), array_agg(DISTINCT type_id), array_agg(DISTINCT source_id)
    INTO lo, hi, types, srcs FROM public.quantity_samples WHERE user_id = p_user;
  -- Every source the user's rows name, for the scrub at the end.
  SELECT coalesce(array_agg(DISTINCT s), '{}') INTO srcs FROM (
    SELECT unnest(srcs) AS s
    UNION SELECT source_id FROM public.category_samples       WHERE user_id = p_user
    UNION SELECT source_id FROM public.workouts               WHERE user_id = p_user
    UNION SELECT source_id FROM public.heartbeat_series       WHERE user_id = p_user
    UNION SELECT source_id FROM public.ecg_samples            WHERE user_id = p_user
    UNION SELECT source_id FROM public.state_of_mind          WHERE user_id = p_user
    UNION SELECT source_id FROM public.medication_dose_events WHERE user_id = p_user
  ) x WHERE s IS NOT NULL;
  IF lo IS NOT NULL THEN
    DELETE FROM public.quantity_samples
     WHERE user_id = p_user AND type_id = ANY (types) AND start_ts BETWEEN lo AND hi;
    GET DIAGNOSTICS n = ROW_COUNT;
  ELSE
    n := 0;
  END IF;
  counts := counts || jsonb_build_object('quantity_samples', n);

  -- workout_series_points is segmented by workout, so naming the workouts
  -- opens only their batches. Taken from the points themselves, not from
  -- workouts: ingest stores points whose workout row is missing or another
  -- user's, and one left behind would stop the user row's delete below.
  SELECT coalesce(array_agg(DISTINCT workout_uuid), '{}') INTO wks
    FROM public.workout_series_points WHERE user_id = p_user;
  DELETE FROM public.workout_series_points WHERE workout_uuid = ANY (wks) AND user_id = p_user;
  GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('workout_series_points', n);
  DELETE FROM public.workout_route_points  WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('workout_route_points', n);
  DELETE FROM public.category_samples      WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('category_samples', n);
  DELETE FROM public.workouts              WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('workouts', n);
  DELETE FROM public.heartbeat_series      WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('heartbeat_series', n);
  DELETE FROM public.ecg_samples           WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('ecg_samples', n);
  DELETE FROM public.state_of_mind         WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('state_of_mind', n);
  DELETE FROM public.medication_dose_events WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('medication_dose_events', n);
  DELETE FROM public.aggregate_samples     WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('aggregate_samples', n);
  DELETE FROM public.activity_summaries    WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('activity_summaries', n);
  DELETE FROM public.deleted_samples       WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('deleted_samples', n);

  -- The continuous aggregate's own rows for this user, which a refresh
  -- would only clear on its next run (and Grafana reads meanwhile).
  SELECT format('%I.%I', materialization_hypertable_schema, materialization_hypertable_name)
    INTO mat FROM timescaledb_information.continuous_aggregates
   WHERE view_schema = 'public' AND view_name = 'quantity_rollups';
  IF mat IS NOT NULL THEN
    EXECUTE format('DELETE FROM %s WHERE user_id = $1', mat) USING p_user;
    GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('quantity_rollups', n);
  END IF;

  -- Device and app names are personal ("Pat's iPhone"), but `sources` is
  -- shared and has no user: blank the name of each source no one else's
  -- records still use. A rename, not a delete, so no table has to check its
  -- foreign keys. The new name is random, so no uploaded source can already
  -- hold it and fail the unique key. The rows are locked first (renaming a
  -- uniquely indexed column conflicts with a foreign-key check), so an
  -- upload starting to use one of them waits the second or two this takes
  -- rather than slipping in between the check and the rename.
  PERFORM 1 FROM public.sources WHERE source_id = ANY (srcs) FOR UPDATE;
  SELECT coalesce(array_agg(DISTINCT u), '{}') INTO used FROM (
    SELECT source_id AS u FROM public.quantity_samples WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.category_samples       WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.workouts               WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.heartbeat_series       WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.ecg_samples            WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.state_of_mind          WHERE source_id = ANY (srcs)
    UNION SELECT source_id FROM public.medication_dose_events WHERE source_id = ANY (srcs)
  ) x;
  UPDATE public.sources SET name = 'removed-' || gen_random_uuid()
   WHERE source_id = ANY (srcs) AND NOT source_id = ANY (used);
  GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('sources_blanked', n);

  DELETE FROM public.batches               WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('batches', n);
  DELETE FROM public.ingest_rejections     WHERE user_id = p_user::text; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('ingest_rejections', n);
  DELETE FROM public.device_tokens         WHERE user_id = p_user; GET DIAGNOSTICS n = ROW_COUNT; counts := counts || jsonb_build_object('device_tokens', n);
  DELETE FROM auth.invites                 WHERE user_id = p_user;
  DELETE FROM auth.signup_requests         WHERE user_id = p_user;
  DELETE FROM auth.accounts                WHERE user_id = p_user;
  -- Last (self_service_users goes with it, by cascade): a table holding this
  -- user that the list above missed keeps its foreign key and fails this
  -- loudly instead of leaving data behind.
  DELETE FROM public.users                 WHERE id = p_user;
  RETURN counts;
END
$$;
REVOKE ALL ON FUNCTION auth.purge_user(bytea, uuid) FROM PUBLIC;

-- ── the signed-in person's own phone ────────────────────────────────────────
-- Records a sync token for the caller's own self-service user, minted by the
-- viewer (32 random bytes, hex — the shape `ingest devices issue` makes; only
-- its SHA-256 over the ASCII hex is stored, as ingest expects). The account
-- row is locked and re-checked, so a token cannot be minted for an account
-- an administrator is disabling at the same moment, and concurrent mints
-- cannot pass the ten-token limit together.
CREATE FUNCTION auth.issue_device_token(p_session bytea, p_token_hash bytea, p_prefix text, p_name text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller record;
  new_id bigint;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.self_service THEN
    RAISE EXCEPTION 'only a signed-in self-service account may connect a phone here' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM auth.accounts WHERE id = caller.account_id AND disabled_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account disabled' USING ERRCODE = '42501';
  END IF;
  IF octet_length(p_token_hash) <> 32 OR p_prefix !~ '^[0-9a-f]{8}$' THEN
    RAISE EXCEPTION 'malformed token' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM public.device_tokens WHERE user_id = caller.user_id AND status = 'active') >= 10 THEN
    RAISE EXCEPTION 'too many connected devices; disconnect one first' USING ERRCODE = '54000';
  END IF;
  INSERT INTO public.device_tokens (token_hash, token_prefix, user_id, name)
  VALUES (p_token_hash, p_prefix, caller.user_id, left(coalesce(p_name, ''), 100))
  RETURNING id INTO new_id;
  RETURN new_id;
END
$$;
REVOKE ALL ON FUNCTION auth.issue_device_token(bytea, bytea, text, text) FROM PUBLIC;

-- The caller's own sync tokens (self-service accounts), for the account page.
CREATE FUNCTION auth.my_devices(p_session bytea)
RETURNS TABLE (id bigint, name text, token_prefix text, status text, created_at timestamptz, last_seen_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT d.id, d.name, d.token_prefix, d.status, d.created_at, d.last_seen_at
    FROM public.device_tokens d
    JOIN auth.session_owner(p_session) o ON o.user_id = d.user_id AND o.self_service
   ORDER BY d.status = 'active' DESC, d.created_at DESC
$$;
REVOKE ALL ON FUNCTION auth.my_devices(bytea) FROM PUBLIC;

-- Revokes one of the caller's own sync tokens; true when one was revoked.
CREATE FUNCTION auth.revoke_my_device(p_session bytea, p_id bigint)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller record;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.self_service THEN
    RAISE EXCEPTION 'only a signed-in self-service account may disconnect a phone here' USING ERRCODE = '42501';
  END IF;
  UPDATE public.device_tokens SET status = 'revoked', revoked_at = now()
   WHERE id = p_id AND user_id = caller.user_id AND status = 'active';
  RETURN FOUND;
END
$$;
REVOKE ALL ON FUNCTION auth.revoke_my_device(bytea, bigint) FROM PUBLIC;

-- A self-service person deletes their own account: disabled at once,
-- sessions ended, sync tokens revoked, and the deletion recorded for an
-- administrator, who purges the data (auth.purge_user). Returns the user,
-- for the notice the viewer sends.
CREATE FUNCTION auth.delete_my_account(p_session bytea)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  caller record;
BEGIN
  SELECT * INTO caller FROM auth.session_owner(p_session);
  IF NOT FOUND OR NOT caller.self_service OR caller.is_admin THEN
    RAISE EXCEPTION 'only a self-service account may delete itself here' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM auth.accounts WHERE id = caller.account_id FOR UPDATE;
  UPDATE auth.accounts SET disabled_at = now(), deletion_requested_at = now() WHERE id = caller.account_id;
  DELETE FROM auth.sessions WHERE account_id = caller.account_id;
  UPDATE public.device_tokens SET status = 'revoked', revoked_at = now()
   WHERE user_id = caller.user_id AND status = 'active';
  RETURN caller.user_id;
END
$$;
REVOKE ALL ON FUNCTION auth.delete_my_account(bytea) FROM PUBLIC;

-- ── housekeeping ────────────────────────────────────────────────────────────
-- Hourly, as a TimescaleDB job, so it happens in the database whether or not
-- anyone opens /admin. It keeps two promises of the privacy policy:
--  * an approved request (name, note, address, browser) is deleted 30 days
--    after the decision; a declined one went when it was declined;
--  * an approved person who never made an account, and has been sent no
--    invite in 30 days, is removed with their invites. Nothing can be stored
--    for them — a sync token needs an account — so their user is empty; one
--    that is not (a foreign key says so) is left in place with a warning.
CREATE PROCEDURE auth.prune_signups(job_id integer, config jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  u uuid;
BEGIN
  DELETE FROM auth.signup_requests WHERE status <> 'pending' AND decided_at < now() - interval '30 days';
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
SELECT add_job('auth.prune_signups', INTERVAL '1 hour', initial_start => now() + INTERVAL '5 minutes');
