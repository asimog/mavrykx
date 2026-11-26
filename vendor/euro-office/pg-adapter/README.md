# PostgreSQL queue and pub/sub adapter

Replaces RabbitMQ (and Erlang) in the Euro-Office server with the PostgreSQL database the
installation already runs. No broker, no extra service, no second runtime.

Derived from the AGPL-3.0 Euro-Office server; the same licence applies.

## Files

| File | Copy to |
|---|---|
| `taskqueuePostgres.js` | `server/Common/sources/taskqueuePostgres.js` |
| `pubsubPostgres.js` | `server/DocService/sources/pubsubPostgres.js` |
| `schema.sql` | run once against the server database |

## Wiring

1. **Dependency.** Add `"pg": "8.14.0"` to `server/Common/package.json` and run `npm ci` there.

2. **Queue type.** In `server/Common/sources/commondefines.js`, add `postgres: 'postgres'` to
   `c_oAscQueueType`.

3. **Task queue export.** At the bottom of `server/Common/sources/taskqueueRabbitMQ.js`, replace
   `module.exports = TaskQueueRabbitMQ;` with:

   ```js
   if (commonDefines.c_oAscQueueType.postgres === cfgQueueType) {
     module.exports = require('./taskqueuePostgres');
   } else {
     module.exports = TaskQueueRabbitMQ;
   }
   ```

4. **Pub/sub export.** At the bottom of `server/DocService/sources/pubsubRabbitMQ.js`, replace
   `module.exports = PubsubRabbitMQ;` with:

   ```js
   if (commonDefines.c_oAscQueueType.postgres === cfgQueueType) {
     module.exports = require('./pubsubPostgres');
   } else {
     module.exports = PubsubRabbitMQ;
   }
   ```

5. **Config.** In `local.json`:

   ```jsonc
   {
     "queue": {
       "type": "postgres",
       "visibilityTimeout": 300,
       "retentionPeriod": 900,
       "postgres": {
         "pollInterval": 200,
         "prefetch": 1,
         "pubsubPollInterval": 1000,
         "pubsubRetentionHours": 24,
         "deadRetentionDays": 7
       }
     }
   }
   ```

   The connection comes from the existing `services.CoAuthoring.sql` block: `dbHost`, `dbPort`,
   `dbName`, `dbUser`, `dbPass`.

The adapter creates its tables on init. Running `schema.sql` first is equivalent and preferred for
production, so the schema is reviewed rather than created at runtime.

## Behaviour

- **At-least-once.** A claim sets `locked_until = now() + visibilityTimeout`. A consumer that dies
  loses its lock, not the message; the row becomes claimable again.
- **Priority.** Higher `priority` first, then oldest id.
- **Redelivery.** `attempts` counts claims. Past `FileConverter.converter.maxRedeliveredCount` the
  message moves to the dead queue; if `simulateErrorResponse` is set, an error response is published.
- **TTL.** `expires_at` mirrors the RabbitMQ message TTL; the janitor moves expired messages to the
  dead queue every 30 seconds.
- **Delayed.** `addDelayed` inserts into the task queue with `available_at` in the future.
- **Dead letters.** Consumed like any queue; `ack` deletes, `nack` requeues.
- **Pub/sub.** One row per message, `LISTEN/NOTIFY` for latency, a one-second poll for missed
  notifications. New subscribers start at the current maximum id. Payloads are `BYTEA`, so the 8 KB
  `NOTIFY` limit does not apply.
- **Cleanup.** Dead letters are kept seven days; pub/sub rows one day. Both configurable.

## Limits

- One database per installation. A shared database between installations would mix queues; do not.
- Polling wakes a consumer every `pollInterval`; 200 ms is fine for conversion work, 50 ms for tests.
- The queue uses the database clock. Keep one clock for the database and the hosts.
- This adapter is not upstream-tested. It is covered by `test/smoke.js` and must be re-run after
  every Euro-Office upgrade.
- Throughput is bounded by PostgreSQL; fine for a firm's conversion load, not for a public
  high-volume service.

## Test

```powershell
npm install
$env:PGPASSWORD = '<onlyoffice password>'
$env:PGPORT = '5433'
node test/smoke.js
```

The test truncates `eo_mq_message` and `eo_pubsub_message`. It checks priority order, delayed
delivery, redelivery after a visibility timeout, dead-lettering with a simulated error response, and
pub/sub fan-out to two subscribers.
