-- 003_watchlist.sql (plan 05): per-user watchlist, offline-first sync (overview §8.5).
CREATE TABLE IF NOT EXISTS watchlist_items (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, symbol TEXT NOT NULL, name TEXT NOT NULL,
  buy_low NUMERIC(18,6), buy_high NUMERIC(18,6), fair NUMERIC(18,6), trim NUMERIC(18,6), sell NUMERIC(18,6),
  memo TEXT NOT NULL DEFAULT '', is_favorite BOOLEAN NOT NULL DEFAULT FALSE, sort_index INT NOT NULL DEFAULT 0,
  checklist JSONB NOT NULL DEFAULT '[]', ladder_history JSONB NOT NULL DEFAULT '[]',
  client_updated_at TIMESTAMPTZ NOT NULL, version BIGINT NOT NULL, deleted_at TIMESTAMPTZ,
  last_status TEXT, last_status_at TIMESTAMPTZ, last_evaluated_price NUMERIC(18,6),   -- server-owned; never bumps version
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, symbol));
CREATE INDEX IF NOT EXISTS idx_watchlist_user_version ON watchlist_items(user_id, version, symbol);
CREATE INDEX IF NOT EXISTS idx_watchlist_live_symbol ON watchlist_items(symbol) WHERE deleted_at IS NULL;
