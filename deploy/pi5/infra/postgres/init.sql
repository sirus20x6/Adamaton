CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- for gen_random_uuid()
-- R2R will create its own schema on first run; we'll create platform.* via Alembic.
