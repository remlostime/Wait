-- 002: shared market-data caches, one row per symbol (overview §8.3)
CREATE TABLE IF NOT EXISTS quote_cache (
  symbol TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  provider TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS history_cache (
  symbol TEXT NOT NULL,
  series TEXT NOT NULL,          -- '1D' | '1W' | 'daily5y'
  payload JSONB NOT NULL,
  provider TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (symbol, series)
);

CREATE TABLE IF NOT EXISTS profile_cache (
  symbol TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS search_cache (
  query TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
