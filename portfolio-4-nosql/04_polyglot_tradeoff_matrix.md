# Polyglot Database Architecture: Model Suitability & CAP Analysis

## 1. Architectural Suitability Matrix

| Dimension | PostgreSQL (Relational) | MongoDB (Document) | Redis (Key-Value) | Neo4j (Graph) |
| :--- | :--- | :--- | :--- | :--- |
| **Domain Role** | Double-entry financial ledger & customer balances. | Polymorphic payment webhooks & KYC files. | Auth token blacklist & fixed-window rate limiting. | Anti-Money Laundering (AML) cyclic mule detection. |
| **Data Structure** | Tabular relations with primary/foreign key integrity. | Hierarchical BSON documents with dynamic fields. | In-memory key-value strings, sorted sets, hashes. | Nodes, typed directed relationships, and properties. |
| **ACID Support** | Full Multi-Statement ACID (Serializable). | Single-Document ACID (Multi-doc via replica sets). | Single-command atomicity (Lua script atomic block). | Graph ACID transactions with lock managers. |
| **Read Latency** | 2 ms – 5 ms | 5 ms – 15 ms | **< 0.5 ms** | 10 ms – 40 ms (deep multi-hop) |
| **Traversal Cost** | Catastrophic $O(n^k)$ recursive JOIN explosion. | Not suited for multi-entity relationship traversal. | Manual indexing required in application memory. | **$O(k)$ index-free adjacency direct pointer chasing.** |

---

## 2. CAP Theorem Evaluation
- **PostgreSQL Ledger (CP):** Under network partition, the ledger rejects ambiguous writes to prevent duplicate balances.
- **Redis Cache (AP):** Favors availability and ultra-low latency; a brief partition falls back to local instance cache.
- **MongoDB Webhooks (CP):** Uses majority write concern (`w: "majority"`) ensuring payment webhooks are durable before ACK.
