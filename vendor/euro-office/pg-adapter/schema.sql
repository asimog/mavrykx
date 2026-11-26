-- Euro-Office PostgreSQL queue and pub/sub schema.
-- Run once per database; the adapter also creates these tables on init.

CREATE TABLE IF NOT EXISTS eo_mq_message (
  id           BIGSERIAL PRIMARY KEY,
  queue        TEXT        NOT NULL,
  payload      BYTEA       NOT NULL,
  priority     INTEGER     NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ,
  attempts     INTEGER     NOT NULL DEFAULT 0,
  locked_by    TEXT,
  locked_until TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS eo_mq_message_claim
  ON eo_mq_message (queue, available_at, priority DESC, id);

CREATE INDEX IF NOT EXISTS eo_mq_message_expiry
  ON eo_mq_message (expires_at)
  WHERE expires_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS eo_pubsub_message (
  id         BIGSERIAL PRIMARY KEY,
  payload    BYTEA       NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS eo_pubsub_message_age
  ON eo_pubsub_message (created_at);
