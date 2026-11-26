/*
 * PostgreSQL-backed pub/sub for the Euro-Office server.
 *
 * Drop-in replacement for DocService/sources/pubsubRabbitMQ.js when
 * `queue.type` is "postgres". Same public surface:
 *
 *   new Pubsub()
 *   init(callback) / initPromise()
 *   publish(message) -> Promise
 *   close() -> Promise
 *   healthCheck() -> Promise<boolean>
 *   events: 'message' (payload string)
 *
 * A message is a row; LISTEN/NOTIFY wakes subscribers, and a one-second poll
 * covers a missed notification or a reconnect. Subscribers start at the current
 * maximum id, so a restart does not replay history. Payloads are BYTEA, so the
 * 8 KB NOTIFY limit does not apply.
 *
 * AGPL-3.0, same as the server it is derived from.
 */

'use strict';

const config = require('config');
const events = require('events');
const util = require('util');
const {Pool} = require('pg');

const cfgSql = config.get('services.CoAuthoring.sql');
const cfgPollInterval =
  Number(config.has('queue.postgres.pubsubPollInterval')
    ? config.get('queue.postgres.pubsubPollInterval')
    : 1000) || 1000;
const cfgRetentionHours =
  Number(config.has('queue.postgres.pubsubRetentionHours')
    ? config.get('queue.postgres.pubsubRetentionHours')
    : 24) || 24;

const CHANNEL = 'eo_pubsub';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS eo_pubsub_message (
  id         BIGSERIAL PRIMARY KEY,
  payload    BYTEA       NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS eo_pubsub_message_age ON eo_pubsub_message (created_at);
`;

function poolConfig() {
  return {
    host: cfgSql.dbHost || '127.0.0.1',
    port: Number(cfgSql.dbPort) || 5432,
    database: cfgSql.dbName || 'onlyoffice',
    user: cfgSql.dbUser || 'onlyoffice',
    password: cfgSql.dbPass || '',
    max: 2,
    application_name: 'euro-office-pubsub',
  };
}

function PubsubPostgres() {
  events.EventEmitter.call(this);
  this.isClose = false;
  this.pool = null;
  this.listener = null;
  this.lastId = 0;
  this.publishStore = [];
  this.timer = null;
  this.draining = false;
  this.ready = null;
}

util.inherits(PubsubPostgres, events.EventEmitter);

PubsubPostgres.prototype.init = function (callback) {
  this.initPromise().then(
    () => callback && callback(null),
    (err) => callback && callback(err)
  );
};

PubsubPostgres.prototype.initPromise = function () {
  if (!this.ready) this.ready = this._init();
  return this.ready;
};

PubsubPostgres.prototype._init = async function () {
  this.pool = new Pool(poolConfig());
  this.pool.on('error', (err) => this.emit('error', err));
  await this.pool.query(SCHEMA);

  const max = await this.pool.query('SELECT COALESCE(MAX(id), 0) AS id FROM eo_pubsub_message');
  this.lastId = Number(max.rows[0].id);

  this.listener = await this.pool.connect();
  this.listener.on('error', (err) => this.emit('error', err));
  this.listener.on('notification', (msg) => {
    if (msg.channel === CHANNEL) this._drain().catch((err) => this.emit('error', err));
  });
  await this.listener.query(`LISTEN ${CHANNEL}`);

  this.timer = setInterval(() => this._drain().catch((err) => this.emit('error', err)), cfgPollInterval);
  this.timer.unref();

  for (const data of this.publishStore) {
    await this._insert(data);
  }
  this.publishStore.length = 0;
};

PubsubPostgres.prototype._insert = async function (data) {
  await this.pool.query(
    `WITH ins AS (
       INSERT INTO eo_pubsub_message (payload) VALUES ($1) RETURNING id
     )
     SELECT id, pg_notify('${CHANNEL}', id::text) FROM ins`,
    [data]
  );
};

PubsubPostgres.prototype._drain = async function () {
  if (this.isClose || this.draining) return;
  this.draining = true;
  try {
    for (;;) {
      const res = await this.pool.query(
        'SELECT id, payload FROM eo_pubsub_message WHERE id > $1 ORDER BY id ASC LIMIT 500',
        [this.lastId]
      );
      if (res.rows.length === 0) break;
      for (const row of res.rows) {
        this.lastId = Number(row.id);
        this.emit('message', row.payload.toString());
      }
      if (res.rows.length < 500) break;
    }
  } finally {
    this.draining = false;
  }
};

PubsubPostgres.prototype.publish = function (message) {
  const data = Buffer.from(message);
  if (!this.ready || !this.pool) {
    this.publishStore.push(data);
    return Promise.resolve();
  }
  return this.ready.then(() => this._insert(data));
};

PubsubPostgres.prototype.close = async function () {
  this.isClose = true;
  if (this.timer) clearInterval(this.timer);
  this.timer = null;
  if (this.listener) {
    try {
      await this.listener.query(`UNLISTEN ${CHANNEL}`);
    } catch (err) {
      /* the connection may already be gone */
    }
    this.listener.release();
    this.listener = null;
  }
  if (this.pool) {
    const pool = this.pool;
    this.pool = null;
    await pool.query(
      `DELETE FROM eo_pubsub_message WHERE created_at < now() - make_interval(hours => $1::int)`,
      [cfgRetentionHours]
    ).catch(() => {});
    await pool.end();
  }
};

PubsubPostgres.prototype.healthCheck = async function () {
  if (!this.pool) return false;
  try {
    await this.pool.query('SELECT 1');
    return true;
  } catch (err) {
    return false;
  }
};

module.exports = PubsubPostgres;
