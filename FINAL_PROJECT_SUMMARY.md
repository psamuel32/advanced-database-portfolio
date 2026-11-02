# Final Project Summary — MIT 8103 Advanced Database Systems

![Course](https://img.shields.io/badge/MIT%208103-Advanced%20Database%20Systems-blueviolet)
![Institution](https://img.shields.io/badge/Miva%20Open%20University-Postgraduate%20Studies-informational)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Neo4j](https://img.shields.io/badge/Neo4j-5.x-4581C3?logo=neo4j&logoColor=white)

- Student Name: Praise Samuel
- Student Email / ID: p.okoro4197@miva.edu.ng
- Programme: Master of Information Technology (MIT)
- Academic Session: 2026/2027 Academic Session — First Semester Continuous Assessment
- Course Code and Title: MIT 8103 Advanced Database Systems
- Submission Channels: Miva LMS (2–3 page documentation) and Private GitHub Repository
- Repository URL: `https://github.com/psamuel32/advanced-database-portfolio`

---

## 1. Selected Organisation and Business Scenario

### 1.1 Organisation Profile
- Organisation Name: ApexPay Global
- System Classification: Multi-Currency Core Digital Banking and High-Throughput Instant Settlement Platform
- Business Mission: ApexPay Global is a licensed financial technology infrastructure provider delivering real-time consumer peer-to-peer transfers, multi-currency wallets (NGN, USD, EUR, GBP), commercial merchant payment gateways, and automated Anti-Money Laundering transaction surveillance across African and international financial corridors.

### 1.2 System Scale and Volume Metrics
- Daily Transaction Throughput: 4,500,000 or more atomic ledger entries posted per 24-hour cycle
- Registered Customers: 2,450,000 retail and merchant customers
- Deposit Accounts: 3,100,000 customer and merchant accounts
- Data Accumulation: approximately 120 GB of relational and audit log data per month
- Read/Write Ratio: 70% reads (balance lookups, statements) to 30% writes (payments, card debits)

### 1.3 Users of the Database and Access Scopes
1. Retail and SME Consumers: query cleared balances, download statement journals, and initiate atomic payments authenticated through row-level security tokens.
2. Commercial Merchants: accept customer checkouts through POS terminals and APIs, and receive automated daily net disbursements.
3. AML and Financial Crime Analysts: investigate suspicious multi-hop transactions and cyclic mule accounts through graph visualisation.
4. Financial Operations and Statutory Auditors: perform continuous double-entry reconciliation, verifying that debits minus credits equal zero.
5. Database Reliability Engineers: manage multi-region replication, Patroni consensus, Citus hash sharding, and point-in-time recovery.

### 1.4 Major Data Stored
1. Customer Identity and KYC: national identifiers, BVN and NIN verification hashes, biometric authentication tokens, and risk tiers (Tiers 1–3).
2. Multi-Currency Deposit Accounts: checking, savings and merchant settlement accounts carrying ISO currency tags and non-negative balance constraints.
3. Immutable Double-Entry Ledger: paired DEBIT and CREDIT journal entries recording every value movement.
4. Payment Cards: PCI-DSS compliant tokenised PAN strings, expiry dates, and dynamic daily spend limits.
5. Fraud Surveillance Telemetry: device fingerprints, IP velocity histories, and inference risk scores.

### 1.5 Key Database Operations Supported
1. Atomic multi-account fund transfers with no race conditions, enforced through `SELECT ... FOR UPDATE`.
2. Idempotency enforcement preventing duplicate charges during network retries.
3. Continuous double-entry reconciliation verifying ledger entries against account snapshot balances.
4. Real-time sliding-window velocity checks flagging rapid automated transfers.
5. Automated transaction reversal with compensatory accounting on payment gateway timeout.
6. Graph-based detection of circular smurfing and mule account networks.
7. Zero-RPO multi-region synchronous replication with automatic quorum failover.

---

## 2. Synthesis of the Five Portfolio Activities

### 2.1 Portfolio 1: Database Design and Relational Modelling

Relational architecture: seven fully normalised relations in PostgreSQL 16 — `customers`, `accounts`, `transactions`, `ledger_entries`, `merchants`, `cards`, and `fraud_alerts`.

Domain constraints enforced:
- Balance invariant: `CHECK (balance >= 0)` at the database kernel, preventing overdraft states.
- Value invariant: `CHECK (amount > 0)` on transactions and ledger entries.
- Surrogate key discipline: global UUIDv4 identifiers preventing identifier enumeration.
- Foreign key policy: `ON DELETE RESTRICT` on accounts and customers, preventing orphaned balance records.

Normalisation progression from UNF to BCNF:
- UNF: raw denormalised reporting export containing repeating customer and multi-account arrays.
- 1NF: repeating groups unnested to atomic scalar values under the composite candidate key `{transaction_id, account_id, entry_seq}`.
- 2NF: partial functional dependencies removed by decomposing into `CUSTOMER_ACCOUNTS`, `TRANSACTIONS`, and `LEDGER_ENTRIES`.
- 3NF: transitive dependencies (`account_id` to `customer_email`, and `customer_email` to `{customer_name, phone, kyc_tier}`) removed by separating `CUSTOMERS` from `ACCOUNTS`.
- BCNF: proved that for every non-trivial functional dependency X to Y, the determinant X is a superkey. The schema achieves BCNF compliance with no loss of dependencies.

### 2.2 Portfolio 2: Query Processing and Performance Optimisation

Three production SQL queries were authored and benchmarked against 28.4 million ledger records and 14.2 million transactions.

Q1, Running Balance Reconciliation (operational). Employs the window function `SUM() OVER (PARTITION BY account_id ORDER BY posted_at ASC, entry_id ASC)` with a CTE to audit running ledger totals against snapshot balances.

```diff
- Seq Scan on ledger_entries (28.4M rows)        22,766.5 ms   347,552 disk blocks
+ Index Scan using idx_ledger_acc_posted              4.19 ms          12 disk blocks
```

Q2, Fraud Velocity Surveillance (security and AML). Analyses a 30-minute sliding window using `DENSE_RANK()` with an aggregate `HAVING COUNT(*) >= 3` filter to detect automated account takeover bursts.

```diff
- Seq Scan on transactions (14.2M rows)            3,591.9 ms   233,493 disk blocks
+ Bitmap Index Scan using idx_tx_velocity_partial     233.1 ms        79 disk blocks
```

> [!NOTE]
> The partial index predicate mirrors the query predicate exactly. Query 2 filters `transaction_type IN ('P2P_TRANSFER', 'CARD_PAYMENT')` and `amount >= 50000.0000`, so `idx_tx_velocity_partial` is built on those two conditions. PostgreSQL selects a partial index only when the query predicate implies the index predicate, so the two definitions must be kept in step.

Q3, Merchant Net Settlement (financial). Aggregates daily transaction volume, nets contract interchange fees, and groups by merchant category code.

```diff
- Hash Join + Seq Scan                           4,445.1 ms   240,507 disk blocks
+ Merge Join (Index Only + Index Scan)           1,647.4 ms    30,385 disk blocks
```

> [!IMPORTANT]
> Indexing is not free. Additional indexes on `transactions` reduced write throughput by approximately 22% through auxiliary B-Tree maintenance. Partial indexes with selective `WHERE` predicates and covering indexes with `INCLUDE` clauses delivered the largest read gains while preserving write throughput.

### 2.3 Portfolio 3: Transactions and Concurrency Control

ACID peer-to-peer transfer (commit path). A sender initiates a 500.00 transfer with a 2.50 fee. The procedure executes `SELECT balance FROM accounts WHERE account_id = ... FOR UPDATE` to acquire row-level exclusive locks, debits the sender by 502.50, credits the recipient by 500.00, credits platform revenue by 2.50, and posts three balanced ledger records. A synchronous `COMMIT` forces the write-ahead log to disk through `fsync`.

```diff
- Balances read without locking; concurrent writers interleave freely
+ SELECT ... FOR UPDATE acquires row-level exclusive locks before any balance is modified
```

Fault injection and overdraft rejection (rollback path). A sender whose cleared balance is below the requested amount attempts a 1,200.00 transfer.

```diff
- Transfer accepted against an insufficient cleared balance
+ ERROR 23514: check_violation (accounts_balance_check)  ->  TRANSACTION ROLLBACK
```

> [!WARNING]
> The rollback script is expected to raise this exception. A run that completes silently would indicate that the balance constraint is not present.

Concurrency and deadlock resolution. Dirty reads, non-repeatable reads and lost updates were evaluated against ANSI SQL-92 isolation levels and PostgreSQL MVCC tuple visibility (`xmin` and `xmax`). Deadlocks were eliminated by enforcing canonical ascending `account_id` lock ordering with `ORDER BY account_id ASC FOR UPDATE`, which prevents cyclic wait conditions rather than relying on optimistic retry loops.

### 2.4 Portfolio 4: NoSQL and Polyglot Persistence Data Models

The portfolio evaluates why a single relational model cannot serve every banking subsystem.

1. Document store (MongoDB). Ingests dynamic polymorphous card network webhooks and unstructured KYC documents. Implemented as a hierarchical BSON collection with nested risk telemetry, compound indexes and aggregation pipelines.
2. Key-value store (Redis). Provides sub-millisecond JWT session blacklist validation and fixed-window API rate limiting. Implemented as an atomic Lua script executing in under 0.5 ms.
3. Graph data model (Neo4j). Detects AML cyclic mule rings through `(:Account)` nodes joined by `[:TRANSFERRED_TO]` relationships. A 3-hop cycle (A to B to C to A) resolves in 14 ms using index-free adjacency, avoiding the growth of recursive joins in SQL.

```diff
- Single relational store carrying the ledger, webhook ingestion, session state and graph traversal
+ Polyglot persistence: MongoDB (documents), Redis (key-value), Neo4j (graph)
```

### 2.5 Portfolio 5: Distributed and Cloud Database Architecture

- Multi-region replication: read/write primary in `europe-west3-a` (Frankfurt), synchronous in-region standby in `europe-west3-b` giving zero data loss (RPO = 0 seconds), and cross-region asynchronous read replicas in `us-east1` (Virginia) and `asia-northeast1` (Tokyo) serving balance enquiries.
- Horizontal sharding and partitioning: Citus and PostgreSQL hash sharding on `account_id` distributes 3.1 million accounts across cluster worker nodes. Ledger entries are colocated on the same shard key, so approximately 95% of join queries execute locally on one node without distributed two-phase commit overhead. Monthly range partitions on `transactions` (for example `transactions_2026_m10`) enable partition pruning and data tiering.
- High availability: target 99.999% availability with RPO = 0 seconds and RTO under 15 seconds, orchestrated by Patroni over an `etcd` consensus cluster with automated leader election and split-brain fencing.
- CAP and PACELC rationale: under partition the ledger prioritises consistency over availability, halting writes if quorum cannot be validated to prevent the creation of phantom money. Under normal operation, writes require synchronous standby confirmation while balance queries route to regional replicas, which is the EC/EL branch of the PACELC formulation.

---

## 3. Technical Reflection: Decisions, Trade-offs and Lessons Learned

1. Write latency versus durability. The most consequential decision was adopting synchronous replication for the in-zone standby. It introduces an unavoidable network round trip of roughly 4 ms on every payment commit, and it is the only mechanism considered here that guarantees zero committed data loss under datacentre failure.
2. Locking bottlenecks under high concurrency. Initial tests produced intermittent deadlocks on concurrent bidirectional transfers. Sorting account identifiers before acquiring locks eliminated every deadlock observed, without introducing optimistic retry loops or weakening isolation.
3. The indexing discipline. Indexes carry a maintenance cost. Unnecessary indexes on the transaction table reduced write throughput by 22%. Selective partial indexes and covering indexes with `INCLUDE` clauses produced the largest read improvements while leaving write throughput intact.

---

## 4. Academic Integrity and AI Use Declaration

In accordance with Section 11 of the MIVA assessment guidelines:

1. AI tools used: Google AI Studio (Gemini) for the initial generation of the portfolio artefacts, and an AI coding assistant used subsequently for line-by-line review.
2. Purpose of use: drafting the initial schema, analytical queries, transaction scripts, NoSQL models and distributed configuration; and assisting with the review and correction of those drafts.
3. Student verification and validation: every artefact was read and reviewed by the student. That review identified and corrected a number of defects, including an invalid UUID literal in the transfer script, a Cypher statement that referenced variables outside their statement scope, a partial index predicate that did not match the query it was meant to serve, a Citus distribution key that would have been rejected at creation time, a stale index definition in the benchmark documentation, and corrupted mathematical notation in the normalisation proof. The functional dependencies in the normalisation proof were checked against relational algebra, and the schema constraints were verified against the DDL.

---

## 5. References

1. A. Silberschatz, H. F. Korth, and S. Sudarshan, Database System Concepts, 7th ed. New York: McGraw-Hill, 2020.
2. PostgreSQL Global Development Group, "PostgreSQL 16 Documentation: Concurrency Control and Index Types," 2024. Available: https://www.postgresql.org/docs/16/
3. M. Kleppmann, Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems. Sebastopol, CA: O'Reilly Media, 2017.
4. D. J. Abadi, "Consistency Tradeoffs in Modern Distributed Database System Design: PACELC," IEEE Computer, vol. 45, no. 2, pp. 37–42, 2012.
5. Miva Open University, "MIT 8103: Advanced Database Systems Course Continuous Assessment Specification," School of Post Graduate Studies, 2026.
