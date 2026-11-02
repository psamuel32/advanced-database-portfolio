# Advanced Database Systems Practical Portfolio (MIT 8103)

![Course](https://img.shields.io/badge/MIT%208103-Advanced%20Database%20Systems-blueviolet)
![Institution](https://img.shields.io/badge/Miva%20Open%20University-Postgraduate%20Studies-informational)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Neo4j](https://img.shields.io/badge/Neo4j-5.x-4581C3?logo=neo4j&logoColor=white)

- Student Name: Praise Samuel
- Student Email / ID: p.okoro4197@miva.edu.ng
- Institution: Miva Open University — School of Post Graduate Studies
- Programme: Master of Information Technology (MIT)
- Academic Session: 2026/2027 Academic Session
- Semester: First Semester Continuous Assessment
- Course Code: MIT 8103 Advanced Database Systems
- Assessment: Continuous Assessment Portfolio
- Submission Channels: LMS (2–3 Page Documentation) and Private GitHub Repository
- Repository URL: `https://github.com/psamuel32/advanced-database-portfolio`

---

## 1. Selected Organisation and Business Scenario

### 1.1 Organisation Profile
- Organisation Name: ApexPay Global
- System Classification: Multi-Currency Core Digital Banking and High-Throughput Instant Settlement Platform
- Nature of System: A multi-currency core digital banking and instant settlement gateway serving retail consumers and commercial merchants. The platform maintains deposit accounts, executes atomic peer-to-peer transfers, enforces a double-entry ledger, processes card authorisations, and performs financial crime screening.

### 1.2 System Scale and Volume Metrics
- Daily Transaction Throughput: 4,500,000 or more atomic ledger entries posted per 24-hour cycle
- Active Accounts: 2,450,000 retail and merchant deposit accounts
- Data Accumulation: approximately 120 GB of relational and audit log data per month
- Read/Write Ratio: 70% reads (balance lookups, statements) to 30% writes (payments, card debits)

### 1.3 Database Users and Access Scopes
1. Retail and SME Customers: query cleared balances, retrieve statement journals, and initiate payments.
2. Commercial Merchants: submit payment transactions through REST APIs and POS terminals, and receive daily net disbursements.
3. AML and Compliance Officers: inspect suspicious transaction volumes and cyclic money laundering networks.
4. Financial Operations and Auditors: verify double-entry equilibrium and reverse anomalous transfers.
5. Database Reliability Engineers (DBRE): maintain replication topology, sharding keys, consensus configuration and backups.

### 1.4 Major Data Stored
1. Customer Identity and KYC: national identity hashes, verification records, biometric tokens, and risk tiers (Tiers 1–3).
2. Multi-Currency Deposit Accounts: checking, savings and merchant settlement accounts carrying ISO currency tags and non-negative balance constraints.
3. Immutable Double-Entry Ledger: paired DEBIT and CREDIT journal entries recording every value movement.
4. Payment Cards: PCI-DSS compliant tokenised PAN strings, expiry dates, and daily spend limits.
5. Fraud Surveillance Telemetry: device fingerprints, IP velocity histories, and model inference risk scores.

### 1.5 Key Database Operations Supported
1. Atomic multi-account fund transfers with row-level locking and no race conditions.
2. Idempotency enforcement preventing duplicate charges during network retries.
3. Continuous double-entry reconciliation verifying cumulative ledger entries against account snapshot balances.
4. Real-time sliding-window velocity checks flagging rapid automated transfers.
5. Automated transaction reversal with compensatory accounting on gateway timeout.
6. Graph-based detection of circular smurfing and mule account networks.
7. Zero-RPO multi-region synchronous replication with quorum-based failover.

---

## 2. Repository Layout

The repository is organised into five portfolio directories, each holding the scripts, configuration files and documentation for one activity.

```
advanced-database-portfolio/
├── README.md                                  # Root overview and execution instructions
├── portfolio-1-database-design/
│   ├── README.md                              # Design documentation and verification steps
│   ├── 01_schema_ddl.sql                      # PostgreSQL DDL with domain constraints
│   ├── 02_erd_specification.md                # Crow's foot entity dictionary and cardinality rules
│   └── 03_normalisation_proof.md              # UNF -> 1NF -> 2NF -> 3NF -> BCNF proof
├── portfolio-2-query-optimisation/
│   ├── README.md                              # Query objectives and benchmark procedure
│   ├── 01_advanced_queries.sql                # Window functions, CTEs and aggregation pipelines
│   ├── 02_execution_plans.json                # Captured plan for query 1 plus benchmark metrics
│   ├── 03_indexing_benchmarks.md              # Latency, buffer and cost comparison tables
│   ├── 04_synthetic_data_generator.sql        # Synthetic dataset matching documented cardinalities
│   └── 05_index_creation.sql                  # Supporting indexes, re-runnable
├── portfolio-3-transactions-concurrency/
│   ├── README.md                              # Transaction test harness
│   ├── 01_acid_transfer_commit.sql            # Atomic transfer with row locks (COMMIT)
│   ├── 02_rollback_fault_injection.sql        # Overdraft fault injection and abort (ROLLBACK)
│   └── 03_isolation_concurrency_study.md      # Isolation levels, MVCC visibility and 2PL ordering
├── portfolio-4-nosql/
│   ├── README.md                              # Polyglot runtime setup
│   ├── 01_mongodb_webhook_events.json         # BSON schema and aggregation pipeline
│   ├── 02_redis_rate_limiter.lua              # Sliding-window token bucket script
│   ├── 03_neo4j_aml_detection.cypher          # Cycle detection over the transfer graph
│   └── 04_polyglot_tradeoff_matrix.md         # Store suitability and CAP evaluation
└── portfolio-5-distributed-cloud/
    ├── README.md                              # Multi-region deployment guide
    ├── 01_replication_sharding_topology.md    # Topology and replication lag calculations
    ├── 02_patroni_cluster_config.yaml         # Patroni consensus and failover configuration
    ├── 03_citus_sharding_setup.sql            # Citus hash sharding and range partitioning
    └── 04_cap_pacelc_resilience_study.md      # Availability targets, RPO/RTO and PACELC analysis
```

---

## 3. Environment Prerequisites and Setup

### 3.1 Software Requirements
- PostgreSQL 16.x (or 15.x) with the `uuid-ossp` and `pgcrypto` extensions
- MongoDB 7.0 or later
- Redis 7.2 or later
- Neo4j 5.x (Community or Enterprise)
- Client tools: `psql`, `mongosh`, `mongoimport`, `redis-cli`, and `cypher-shell`

> [!IMPORTANT]
> The Portfolio 1 schema must be applied before any Portfolio 2 or Portfolio 3 script is executed. The analytical queries and the transaction tests both depend on the tables, constraints and triggers that it defines.

### 3.2 Execution Sequence

```bash
# 1. Clone the repository
git clone https://github.com/psamuel32/advanced-database-portfolio.git
cd advanced-database-portfolio

# 2. Create the PostgreSQL database and apply the schema
createdb -U postgres apexpay_db
psql -U postgres -d apexpay_db -f portfolio-1-database-design/01_schema_ddl.sql

# 3. Run the analytical and operational queries
psql -U postgres -d apexpay_db -f portfolio-2-query-optimisation/01_advanced_queries.sql

# 4. Execute the ACID transaction tests (commit and rollback paths)
psql -U postgres -d apexpay_db -f portfolio-3-transactions-concurrency/01_acid_transfer_commit.sql
psql -U postgres -d apexpay_db -f portfolio-3-transactions-concurrency/02_rollback_fault_injection.sql

# 5. Execute the NoSQL workloads
mongoimport --db apexpay_events --collection webhook_events --file portfolio-4-nosql/01_mongodb_webhook_events.json --jsonArray
redis-cli --eval portfolio-4-nosql/02_redis_rate_limiter.lua ratelimit:102.89.23.11 , 100
cypher-shell -u neo4j -p password -f portfolio-4-nosql/03_neo4j_aml_detection.cypher
```

> [!WARNING]
> The rollback script in Portfolio 3 aborts a transaction by design. A `check_violation` raised against `accounts_balance_check` is the expected result, not a configuration fault.

---

## 4. Portfolio Index

| Directory | Activity | Principal Evidence |
| :--- | :--- | :--- |
| `portfolio-1-database-design` | Relational schema, constraints, ERD and normalisation | `01_schema_ddl.sql`, `02_erd_specification.md`, `03_normalisation_proof.md` |
| `portfolio-2-query-optimisation` | Complex SQL, execution plans and indexing | `01_advanced_queries.sql`, `02_execution_plans.json`, `03_indexing_benchmarks.md`, `04_synthetic_data_generator.sql`, `05_index_creation.sql` |
| `portfolio-3-transactions-concurrency` | ACID guarantees, fault injection and isolation | `01_acid_transfer_commit.sql`, `02_rollback_fault_injection.sql`, `03_isolation_concurrency_study.md` |
| `portfolio-4-nosql` | Document, key-value and graph persistence | `01_mongodb_webhook_events.json`, `02_redis_rate_limiter.lua`, `03_neo4j_aml_detection.cypher`, `04_polyglot_tradeoff_matrix.md` |
| `portfolio-5-distributed-cloud` | Replication, sharding, failover and disaster recovery | `01_replication_sharding_topology.md`, `02_patroni_cluster_config.yaml`, `03_citus_sharding_setup.sql`, `04_cap_pacelc_resilience_study.md` |

---

## 5. Category Evidence Mapping

| Category Item | Description | Evidence File |
| :--- | :--- | :--- |
| I. SQL scripts | Production DDL, analytical queries, ACID transactions | `portfolio-1/01_schema_ddl.sql`, `portfolio-2/01_advanced_queries.sql`, `portfolio-3/01_acid_transfer_commit.sql` |
| II. Database schemas | Relational DDL and NoSQL document models | `portfolio-1/01_schema_ddl.sql`, `portfolio-4/01_mongodb_webhook_events.json` |
| III. ER diagrams and models | Crow's foot entity dictionary and graph data models | `portfolio-1/02_erd_specification.md`, `portfolio-4/03_neo4j_aml_detection.cypher` |
| IV. NoSQL implementations | Document (MongoDB), key-value (Redis) and graph (Neo4j) | `portfolio-4/01_mongodb_webhook_events.json`, `portfolio-4/02_redis_rate_limiter.lua`, `portfolio-4/03_neo4j_aml_detection.cypher` |
| V. Query plans and performance | EXPLAIN ANALYZE trees and indexing benchmarks | `portfolio-2/02_execution_plans.json`, `portfolio-2/03_indexing_benchmarks.md` |
| VI. Screenshots, configs, test results | Cluster configuration, fault injection tests and Patroni YAML | `portfolio-3/02_rollback_fault_injection.sql`, `portfolio-5/02_patroni_cluster_config.yaml`, `portfolio-5/03_citus_sharding_setup.sql` |
| VII. Technical documentation and READMEs | Folder READMEs, root README and submission summary | `README.md`, `LMS_SUBMISSION.md`, and the `README.md` in each portfolio folder |
