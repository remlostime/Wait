-- 001: anonymous users and the Postgres token-bucket table (overview §8.3)
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  anonymous_id TEXT NOT NULL,
  watchlist_version BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_anonymous_id ON users(anonymous_id);

CREATE TABLE IF NOT EXISTS rate_buckets (
  key TEXT PRIMARY KEY,
  tokens DOUBLE PRECISION NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  blocked_until TIMESTAMPTZ
);
