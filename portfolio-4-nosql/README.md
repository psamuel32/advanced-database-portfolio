# Portfolio 4: NoSQL and Advanced Data Models

![MongoDB](https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Neo4j](https://img.shields.io/badge/Neo4j-5.x-4581C3?logo=neo4j&logoColor=white)

Author: Praise Samuel (p.okoro4197@miva.edu.ng)

---

## 1. Rationale

A relational model is the correct choice for the double-entry ledger, but it is a poor fit for high-velocity session state, polymorphous external webhook payloads, and multi-hop fraud detection.

```diff
- Single relational store carrying the ledger, webhook ingestion, session state and graph traversal
+ Polyglot persistence: MongoDB (documents), Redis (key-value), Neo4j (graph)
```

---

## 2. Model Selection

| Requirement | Store Selected | Rationale |
| :--- | :--- | :--- |
| Card network webhooks and KYC documents | MongoDB (document) | Payload shape varies by network and issuer; document nesting avoids a wide sparse relational table |
| Session revocation and API rate limiting | Redis (key-value) | Atomic script execution measured below 0.5 ms; the counters are ephemeral and need no durability |
| Circular mule ring detection | Neo4j (graph) | Index-free adjacency resolves a 3-hop cycle in 14 ms, where the equivalent SQL requires recursive self-joins over the ledger |

> [!NOTE]
> The graph model matters most at the margin. Detecting a cycle of the form account to account to account to account is a fixed-cost pointer traversal in Neo4j, but the same question expressed in SQL grows with the join depth and degrades sharply beyond the second hop.

---

## 3. File Directory

- `01_mongodb_webhook_events.json`: Extension JSON sample documents for the `webhook_events` collection, loaded with `mongoimport --jsonArray`.
- `02_redis_rate_limiter.lua`: Redis Lua script implementing a fixed-window request rate limiter.
- `03_neo4j_aml_detection.cypher`: Graph model construction and cycle detection traversal.
- `04_polyglot_tradeoff_matrix.md`: Store suitability rationale and CAP theorem trade-off analysis.

---

## 4. Execution Commands

```bash
# 1. Load the sample documents, then run the aggregation pipeline
mongoimport --db apexpay_events --collection webhook_events --file 01_mongodb_webhook_events.json --jsonArray

mongosh apexpay_events --eval '
db.webhook_events.aggregate([
  { $match: { "timestamp": { $gte: new Date(Date.now() - 3600000) } } },
  { $group: { _id: "$payload.risk_telemetry.ip_address", count: { $sum: 1 } } }
]);'

# 2. Redis rate limiter: limit 100 requests per 60-second window
redis-cli SCRIPT LOAD "$(cat 02_redis_rate_limiter.lua)"
redis-cli EVAL "$(cat 02_redis_rate_limiter.lua)" 1 "ratelimit:102.89.23.11" 100 60

# 3. Neo4j Cypher traversal
cypher-shell -u neo4j -p password -f 03_neo4j_aml_detection.cypher
```

> [!IMPORTANT]
> The Redis script is invoked with `EVAL` rather than a sequence of separate commands. Rate limiting must be atomic, because a read-then-write pair issued as two round trips allows concurrent requests to observe the same counter value and both proceed.

> [!NOTE]
> The limiter is a fixed-window counter, not a sliding window: the window starts on the first request and expires 60 seconds later, so a client can in principle send the full quota at the end of one window and again at the start of the next. A sliding-window variant would store request timestamps in a sorted set (`ZADD` / `ZREMRANGEBYSCORE` / `ZCARD`) instead of a single counter.
