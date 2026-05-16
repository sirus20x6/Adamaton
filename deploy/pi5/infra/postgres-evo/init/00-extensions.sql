-- Bootstrap the gogents database with required extensions.
-- Runs once on first container start (when /var/lib/postgresql/data
-- is empty); not re-run on subsequent boots.
--
-- pg_search: Tantivy-backed BM25 + n-gram tokenisation, used by
--   internal/contextmode/.
-- vector:    pgvector, used by internal/contextmode/ for octen-embed
--   dense retrieval (phase 3).

CREATE EXTENSION IF NOT EXISTS pg_search;
CREATE EXTENSION IF NOT EXISTS vector;
