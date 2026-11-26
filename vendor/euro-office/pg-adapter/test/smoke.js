'use strict';

/*
 * Smoke test for the PostgreSQL queue and pub/sub adapter.
 *
 * Run against a database that the server will use:
 *   PGPASSWORD=<onlyoffice password> node test/smoke.js
 *
 * Env: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.
 * The test truncates eo_mq_message and eo_pubsub_message.
 */

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert');

const db = {
  dbHost: process.env.PGHOST || '127.0.0.1',
  dbPort: Number(process.env.PGPORT || 5433),
  dbName: process.env.PGDATABASE || 'onlyoffice',
  dbUser: process.env.PGUSER || 'onlyoffice',
  dbPass: process.env.PGPASSWORD || 'onlyoffice',
};

const configDir = fs.mkdtempSync(path.join(os.tmpdir(), 'eo-pg-adapter-'));
fs.writeFileSync(
  path.join(configDir, 'default.json'),
  JSON.stringify({
    queue: {
      type: 'postgres',
      visibilityTimeout: 1,
      retentionPeriod: 60,
      postgres: {pollInterval: 50, prefetch: 1, pubsubPollInterval: 100},
    },
    services: {CoAuthoring: {sql: db}},
    FileConverter: {converter: {maxRedeliveredCount: 2}},
  })
);
fs.writeFileSync(path.join(configDir, 'test.json'), '{}');
process.env.NODE_CONFIG_DIR = configDir;
process.env.NODE_ENV = 'test';

const {Client} = require('pg');
const TaskQueuePostgres = require('../taskqueuePostgres');
const PubsubPostgres = require('../pubsubPostgres');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function poolConfig() {
  return {
    host: db.dbHost,
    port: db.dbPort,
    database: db.dbName,
    user: db.dbUser,
    password: db.dbPass,
  };
}

async function clean() {
  const client = new Client(poolConfig());
  await client.connect();
  try {
    const schema = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');
    await client.query(schema);
    await client.query('TRUNCATE eo_mq_message, eo_pubsub_message RESTART IDENTITY');
  } finally {
    await client.end();
  }
}

async function testOrdering() {
  const q = new TaskQueuePostgres();
  await q.initPromise(true, true, true, true, true, true);
  const seen = [];
  q.on('task', (payload, ack) => {
    seen.push(JSON.parse(payload).n);
    setTimeout(ack, 10);
  });

  await q.addTask({n: 1}, 1);
  await q.addTask({n: 5}, 5);
  await q.addTask({n: 3}, 3);
  await q.addDelayed({n: 'delayed'}, 400, true);

  await sleep(2600);
  await q.close();
  assert.deepStrictEqual(seen, [5, 3, 1, 'delayed'], `order was ${JSON.stringify(seen)}`);
  console.log('ok: priority order and delayed delivery');
}

async function testRedelivery() {
  const producer = new TaskQueuePostgres();
  await producer.initPromise(true, false, false, false, false, false);
  await producer.addTask({n: 'dead'}, 0);
  await producer.close();

  // Each consumer claims and dies without acknowledging. The lock expires, the
  // next consumer claims it again, and the third claim exceeds maxRedelivered.
  for (let i = 0; i < 2; i += 1) {
    const q = new TaskQueuePostgres();
    await q.initPromise(false, false, true, false, false, false);
    await sleep(400);
    await q.close();
    await sleep(1200);
  }

  const q = new TaskQueuePostgres((payload) => ({error: 'simulated', original: payload}));
  await q.initPromise(false, false, true, true, true, false);
  const dead = [];
  const responses = [];
  q.on('response', (payload, ack) => {
    responses.push(JSON.parse(payload));
    ack();
  });
  q.on('dead', (payload, ack) => {
    dead.push(JSON.parse(payload).n);
    ack();
  });

  await sleep(2000);
  await q.close();
  assert.ok(dead.includes('dead'), `no dead event; responses=${JSON.stringify(responses)}`);
  assert.ok(responses.some((r) => r.error === 'simulated'), 'no simulated error response');
  console.log('ok: redelivery after visibility timeout and dead letter');
}

async function testPubsub() {
  const sub1 = new PubsubPostgres();
  const sub2 = new PubsubPostgres();
  const pub = new PubsubPostgres();
  await sub1.initPromise();
  await sub2.initPromise();
  await pub.initPromise();
  const got1 = [];
  const got2 = [];
  sub1.on('message', (m) => got1.push(m));
  sub2.on('message', (m) => got2.push(m));
  await pub.publish('hello-1');
  await pub.publish('hello-2');
  await sleep(800);
  await Promise.all([sub1.close(), sub2.close(), pub.close()]);
  assert.deepStrictEqual(got1, ['hello-1', 'hello-2'], `sub1 got ${JSON.stringify(got1)}`);
  assert.deepStrictEqual(got2, ['hello-1', 'hello-2'], `sub2 got ${JSON.stringify(got2)}`);
  console.log('ok: pub/sub fan-out');
}

async function main() {
  await clean();
  await testOrdering();
  await testRedelivery();
  await testPubsub();
  console.log('all adapter checks passed');
}

main().catch(async (err) => {
  console.error(err);
  process.exit(1);
});
