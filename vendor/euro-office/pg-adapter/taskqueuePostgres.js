/*
 * PostgreSQL-backed task queue for the Euro-Office server.
 *
 * Drop-in replacement for Common/sources/taskqueueRabbitMQ.js when
 * `queue.type` is "postgres". It keeps the RabbitMQ adapter's public surface:
 *
 *   new TaskQueue(simulateErrorResponse)
 *   init / initPromise(isAddTask, isAddResponse, isAddTaskReceive,
 *                      isAddResponseReceive, isEmitDead, isAddDelayed)
 *   addTask(task, priority, opt_expiration, opt_headers)
 *   addResponse(task, opt_requireConfirm)
 *   addDelayed(task, ttl, opt_requireConfirm)
 *   close / closeOrWait / healthCheck
 *   events: 'task' (payload, ack)
 *           'response' (payload, ack, isLive)
 *           'dead' (payload, ack, nack, isLive)
 *
 * Semantics:
 * - one row per message; `FOR UPDATE SKIP LOCKED` gives competing consumers
 * - a claim sets locked_until to now() + visibilityTimeout; an expired lock is
 *   claimable again, so a crashed consumer loses its message, not the queue
 * - attempts counts claims; after maxRedeliveredCount the message moves to the
 *   dead queue and, when configured, a simulated error response is published
 * - expires_at implements the RabbitMQ message TTL; the janitor moves expired
 *   messages to the dead queue
 * - addDelayed inserts into the task queue with available_at in the future
 *
 * AGPL-3.0, same as the server it is derived from.
 */

'use strict';

const config = require('config');
const events = require('events');
const util = require('util');
const {Pool} = require('pg');

const cfgSql = config.get('services.CoAuthoring.sql');
const cfgVisibilityTimeout = Number(config.get('queue.visibilityTimeout'));
const cfgRetentionPeriod = Number(config.get('queue.retentionPeriod'));
const cfgMaxRedelivered =
  Number(config.has('FileConverter.converter.maxRedeliveredCount')
    ? config.get('FileConverter.converter.maxRedeliveredCount')
    : 10) || 10;
const cfgPollInterval =
  Number(config.has('queue.postgres.pollInterval') ? config.get('queue.postgres.pollInterval') : 200) || 200;
const cfgPrefetch =
  Number(config.has('queue.postgres.prefetch') ? config.get('queue.postgres.prefetch') : 1) || 1;
const cfgDeadRetentionDays =
  Number(config.has('queue.postgres.deadRetentionDays') ? config.get('queue.postgres.deadRetentionDays') : 7) || 7;

const QUEUE_TASK = 'converttask';
const QUEUE_RESPONSE = 'convertresponse';
const QUEUE_DEAD = 'convertdead';
const DEAD_MOVE =
  `WITH moved AS (
     DELETE FROM eo_mq_message WHERE id = $1
     RETURNING payload, priority, attempts
   )
   INSERT INTO eo_mq_message (queue, payload, priority, available_at, attempts)
   SELECT '${QUEUE_DEAD}', payload, priority, now(), attempts FROM moved`;

const SCHEMA = `
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
  ON eo_mq_message (expires_at) WHERE expires_at IS NOT NULL;
`;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function poolConfig() {
  return {
    host: cfgSql.dbHost || '127.0.0.1',
    port: Number(cfgSql.dbPort) || 5432,
    database: cfgSql.dbName || 'onlyoffice',
    user: cfgSql.dbUser || 'onlyoffice',
    password: cfgSql.dbPass || '',
    max: 4,
    application_name: 'euro-office-queue',
  };
}

function TaskQueuePostgres(simulateErrorResponse) {
  events.EventEmitter.call(this);
  this.isClose = false;
  this.simulateErrorResponse = simulateErrorResponse;
  this.pool = null;
  this.instanceId = `eo-${process.pid}-${Date.now()}`;
  this.loops = [];
  this.janitor = null;
  this.ready = null;
}

util.inherits(TaskQueuePostgres, events.EventEmitter);

TaskQueuePostgres.prototype.init = function (
  isAddTask, isAddResponse, isAddTaskReceive, isAddResponseReceive, isEmitDead, isAddDelayed, callback
) {
  this.initPromise(
    isAddTask, isAddResponse, isAddTaskReceive, isAddResponseReceive, isEmitDead, isAddDelayed
  ).then(
    () => callback && callback(null),
    (err) => callback && callback(err)
  );
};

TaskQueuePostgres.prototype.initPromise = function (
  isAddTask, isAddResponse, isAddTaskReceive, isAddResponseReceive, isEmitDead, isAddDelayed
) {
  if (!this.ready) {
    this.ready = this._init(
      isAddTask, isAddResponse, isAddTaskReceive, isAddResponseReceive, isEmitDead, isAddDelayed
    );
  }
  return this.ready;
};

TaskQueuePostgres.prototype._init = async function (
  isAddTask, isAddResponse, isAddTaskReceive, isAddResponseReceive, isEmitDead, isAddDelayed
) {
  this.pool = new Pool(poolConfig());
  this.pool.on('error', (err) => this.emit('error', err));
  await this.pool.query(SCHEMA);

  if (isAddTaskReceive) {
    this.loops.push(this._consumerLoop(QUEUE_TASK, 'task', cfgPrefetch));
  }
  if (isAddResponseReceive) {
    this.loops.push(this._consumerLoop(QUEUE_RESPONSE, 'response', Math.max(cfgPrefetch, 16)));
  }
  if (isEmitDead) {
    this.loops.push(this._consumerLoop(QUEUE_DEAD, 'dead', Math.max(cfgPrefetch, 16)));
  }
  if (isAddDelayed || isAddTask || isAddResponse || isEmitDead) {
    this.janitor = setInterval(() => this._sweep().catch((err) => this.emit('error', err)), 30000);
    this.janitor.unref();
  }
};

TaskQueuePostgres.prototype._consumerLoop = async function (queue, kind, prefetch) {
  const inFlight = new Set();
  while (!this.isClose) {
    if (inFlight.size >= prefetch) {
      await sleep(25);
      continue;
    }
    let row;
    try {
      row = await this._claim(queue);
    } catch (err) {
      this.emit('error', err);
      await sleep(Math.max(cfgPollInterval, 500));
      continue;
    }
    if (!row) {
      await sleep(cfgPollInterval);
      continue;
    }
    if (row.attempts > cfgMaxRedelivered && queue !== QUEUE_DEAD) {
      await this._toDead(row.id, row.payload);
      continue;
    }
    const payload = row.payload.toString();
    const lived = new Promise((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        inFlight.delete(lived);
        resolve();
      };
      const ack = () => this._ack(row.id).finally(finish);
      const nack = () => this._nack(row.id, queue, row.attempts, row.payload).finally(finish);
      const isLive = () => !this.isClose;
      if (kind === 'task') {
        this.emit('task', payload, ack);
      } else if (kind === 'response') {
        this.emit('response', payload, ack, isLive);
      } else {
        this.emit('dead', payload, ack, nack, isLive);
      }
      // A handler that never settles would otherwise hold a slot forever.
      setTimeout(finish, (cfgVisibilityTimeout + 30) * 1000).unref();
    });
    inFlight.add(lived);
  }
};

TaskQueuePostgres.prototype._claim = async function (queue) {
  const res = await this.pool.query(
    `WITH next AS (
       SELECT id FROM eo_mq_message
       WHERE queue = $1
         AND available_at <= now()
         AND (locked_until IS NULL OR locked_until < now())
         AND (expires_at IS NULL OR expires_at > now())
       ORDER BY priority DESC, id ASC
       FOR UPDATE SKIP LOCKED
       LIMIT 1
     )
     UPDATE eo_mq_message m
     SET locked_by = $2,
         locked_until = now() + make_interval(secs => $3::double precision),
         attempts = m.attempts + 1
     FROM next
     WHERE m.id = next.id
     RETURNING m.id, m.payload, m.attempts`,
    [queue, this.instanceId, cfgVisibilityTimeout]
  );
  return res.rows[0];
};

TaskQueuePostgres.prototype._ack = function (id) {
  return this.pool.query('DELETE FROM eo_mq_message WHERE id = $1', [id]);
};

TaskQueuePostgres.prototype._nack = async function (id, queue, attempts, payload) {
  if (queue === QUEUE_DEAD) {
    await this.pool.query(
      `UPDATE eo_mq_message
       SET locked_by = NULL, locked_until = NULL, available_at = now()
       WHERE id = $1`,
      [id]
    );
    return;
  }
  if (attempts >= cfgMaxRedelivered) {
    await this._toDead(id, payload);
    return;
  }
  await this.pool.query(
    `UPDATE eo_mq_message
     SET locked_by = NULL, locked_until = NULL, available_at = now()
     WHERE id = $1`,
    [id]
  );
};

TaskQueuePostgres.prototype._toDead = async function (id, payload) {
  await this.pool.query(DEAD_MOVE, [id]);
  if (typeof this.simulateErrorResponse === 'function' && payload) {
    try {
      await this.addResponse(this.simulateErrorResponse(payload.toString()));
    } catch (err) {
      this.emit('error', err);
    }
  }
};

TaskQueuePostgres.prototype._sweep = async function () {
  if (this.isClose) return;
  await this.pool.query(
    `WITH expired AS (
       DELETE FROM eo_mq_message
       WHERE queue <> '${QUEUE_DEAD}'
         AND expires_at IS NOT NULL
         AND expires_at <= now()
       RETURNING payload, priority, attempts
     )
     INSERT INTO eo_mq_message (queue, payload, priority, available_at, attempts)
     SELECT '${QUEUE_DEAD}', payload, priority, now(), attempts FROM expired`
  );
  await this.pool.query(
    `DELETE FROM eo_mq_message
     WHERE queue = '${QUEUE_DEAD}'
       AND created_at < now() - make_interval(days => $1::int)`,
    [cfgDeadRetentionDays]
  );
};

TaskQueuePostgres.prototype.addTask = function (task, priority, opt_expiration, _opt_headers) {
  if (task && typeof task.setVisibilityTimeout === 'function') {
    task.setVisibilityTimeout(cfgVisibilityTimeout);
  }
  const ttl = undefined !== opt_expiration ? Number(opt_expiration) : cfgRetentionPeriod * 1000;
  return this._insert(QUEUE_TASK, Buffer.from(JSON.stringify(task)), priority || 0, 0, ttl);
};

TaskQueuePostgres.prototype.addResponse = function (task, opt_requireConfirm) {
  return this._insert(
    QUEUE_RESPONSE, Buffer.from(JSON.stringify(task)), 0, 0, cfgRetentionPeriod * 1000
  ).catch((err) => {
    if (opt_requireConfirm) throw err;
  });
};

TaskQueuePostgres.prototype.addDelayed = function (task, ttl, opt_requireConfirm) {
  return this._insert(QUEUE_TASK, Buffer.from(JSON.stringify(task)), 0, Number(ttl) || 0, null).catch((err) => {
    if (opt_requireConfirm) throw err;
  });
};

TaskQueuePostgres.prototype._insert = async function (queue, payload, priority, delayMs, ttlMs) {
  if (!this.ready) throw new Error('task queue is not initialised');
  await this.ready;
  const params = [queue, payload, priority, delayMs, ttlMs === null ? null : ttlMs];
  await this.pool.query(
    `INSERT INTO eo_mq_message (queue, payload, priority, available_at, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(secs => $4::double precision / 1000.0),
             CASE WHEN $5::double precision IS NULL THEN NULL
                  ELSE now() + make_interval(secs => $5::double precision / 1000.0) END)`,
    params
  );
};

TaskQueuePostgres.prototype.close = async function () {
  this.isClose = true;
  if (this.janitor) clearInterval(this.janitor);
  this.janitor = null;
  await Promise.allSettled(this.loops);
  this.loops = [];
  if (this.pool) {
    const pool = this.pool;
    this.pool = null;
    await pool.end();
  }
};

TaskQueuePostgres.prototype.closeOrWait = function () {
  return this.close();
};

TaskQueuePostgres.prototype.healthCheck = async function () {
  if (!this.pool) return false;
  try {
    await this.pool.query('SELECT 1');
    return true;
  } catch (err) {
    return false;
  }
};

module.exports = TaskQueuePostgres;
