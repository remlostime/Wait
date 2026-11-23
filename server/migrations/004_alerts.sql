-- 004_alerts.sql (plan 06): APNs device tokens, alert events, daily job runs
CREATE TABLE IF NOT EXISTS device_tokens (
  token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox','production')), bundle_id TEXT NOT NULL DEFAULT 'com.chenkai.wait',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_success_at TIMESTAMPTZ);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE TABLE IF NOT EXISTS alert_events (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, symbol TEXT NOT NULL,
  trading_date DATE NOT NULL, status TEXT NOT NULL, previous_status TEXT, price NUMERIC(18,6) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), sent_at TIMESTAMPTZ, attempts INT NOT NULL DEFAULT 0,
  UNIQUE (user_id, symbol, trading_date, status));
CREATE TABLE IF NOT EXISTS alert_job_runs (
  trading_date DATE PRIMARY KEY, status TEXT NOT NULL,      -- running | completed | holiday
  started_at TIMESTAMPTZ NOT NULL, finished_at TIMESTAMPTZ, stats JSONB NOT NULL DEFAULT '{}');
