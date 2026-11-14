-- MERA Fuel Confirmation: atomic, database-backed rate limiting.
-- Apply through the Supabase migration mechanism, as a privileged migration role.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO service_role;

CREATE TABLE IF NOT EXISTS private.fuel_confirmation_rate_limits (
  identifier text NOT NULL,
  action text NOT NULL CHECK (action IN ('lookup', 'confirm')),
  window_start timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts >= 1),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fuel_confirmation_rate_limits_pk PRIMARY KEY (identifier, action, window_start)
);
REVOKE ALL ON private.fuel_confirmation_rate_limits FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.check_fuel_confirmation_rate_limit(
  p_identifier text,
  p_action text,
  p_max_attempts integer,
  p_window_seconds integer DEFAULT 60
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_window_start timestamptz;
  v_attempts integer;
BEGIN
  IF p_identifier IS NULL OR p_identifier !~ '^[0-9a-f]{64}$'
     OR p_action IS NULL OR p_action NOT IN ('lookup', 'confirm')
     OR p_max_attempts IS NULL OR p_max_attempts NOT BETWEEN 1 AND 1000
     OR p_window_seconds IS NULL OR p_window_seconds NOT BETWEEN 1 AND 3600 THEN
    RAISE EXCEPTION 'Invalid rate-limit parameters';
  END IF;

  v_window_start := pg_catalog.to_timestamp(
    pg_catalog.floor(
      EXTRACT(EPOCH FROM clock_timestamp()) / p_window_seconds
    ) * p_window_seconds
  );

  INSERT INTO private.fuel_confirmation_rate_limits
    (identifier, action, window_start, attempts, updated_at)
  VALUES (p_identifier, p_action, v_window_start, 1, pg_catalog.now())
  ON CONFLICT (identifier, action, window_start)
  DO UPDATE SET
    attempts = private.fuel_confirmation_rate_limits.attempts + 1,
    updated_at = pg_catalog.now()
  RETURNING attempts INTO v_attempts;

  RETURN v_attempts <= p_max_attempts;
END;
$$;

-- Restrict direct calls to the backend service role.
REVOKE ALL ON FUNCTION public.check_fuel_confirmation_rate_limit(text, text, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_fuel_confirmation_rate_limit(text, text, integer, integer)
  TO service_role;

-- Expired rows are NOT deleted automatically; run periodic cleanup after rollout.
CREATE INDEX IF NOT EXISTS idx_fuel_confirmation_rate_limits_updated_at
  ON private.fuel_confirmation_rate_limits (updated_at);

