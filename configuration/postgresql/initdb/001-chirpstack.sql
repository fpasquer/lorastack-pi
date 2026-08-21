-- Executed once by the postgres container on first initialization
-- (against the database named by POSTGRES_DB, i.e. "chirpstack").
-- pg_trgm is required by ChirpStack v4.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
