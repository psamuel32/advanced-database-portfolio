# Portfolio 2: Query Processing and Performance Optimisation

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Queries](https://img.shields.io/badge/complex%20queries-3-informational)
![Speedup](https://img.shields.io/badge/indexing%20speedup-up%20to%205436x-brightgreen)

Author: Praise Samuel (p.okoro4197@miva.edu.ng)

---

## 1. Scope of Work

This directory contains the query tuning evidence for the ApexPay dataset:
- Three complex SQL queries covering operational, security and financial settlement problems.
- Execution plans captured with `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)`.
- Before-and-after indexing measurements at plan and buffer level.
- Analysis of PostgreSQL planner costing, buffer usage and scan operator selection.

> [!IMPORTANT]
> Every latency figure below was measured against 28.4 million `ledger_entries` rows and 14.2 million `transactions` rows. Absolute timings are not comparable against differently sized datasets; only the plan shape and buffer counts transfer between environments.

---

## 2. Query Portfolio

| Query | Purpose | Techniques Applied |
| :--- | :--- | :--- |
| Q1 Running Balance Reconciliation | Audits running ledger totals against account snapshot balances | Window function `SUM() OVER (PARTITION BY account_id ORDER BY posted_at, entry_id)` with a CTE |
| Q2 Fraud Velocity Surveillance | Detects high-frequency multi-account outflow bursts inside a 30-minute window | `DENSE_RANK()` over a sliding window with an aggregate `HAVING` filter |
| Q3 Merchant Net Settlement | Nets daily transaction volume against contracted interchange fees | Grouping by merchant category and fee tier |

---

## 3. Measured Optimisation Results

### 3.1 Q1 Running Balance Reconciliation

```diff
- Seq Scan on ledger_entries (28.4M rows)        22,766.5 ms   347,552 disk blocks
+ Index Scan using idx_ledger_acc_posted              4.19 ms          12 disk blocks
```

Composite ordering on `(account_id, posted_at ASC, entry_id ASC)` matches the window specification exactly. The executor therefore reads B-Tree leaves in already sorted order and the in-memory quicksort node is eliminated entirely.

### 3.2 Q2 Fraud Velocity Surveillance

```diff
- Seq Scan on transactions (14.2M rows)            3,591.9 ms   233,493 disk blocks
+ Bitmap Index Scan using idx_tx_velocity_partial     233.1 ms        79 disk blocks
```

The partial predicate `WHERE transaction_type IN ('P2P_TRANSFER', 'CARD_PAYMENT') AND amount >= 50000.0000` restricts the index to high-value customer-initiated transfers and matches the query predicate exactly. The captured plan moved from a Seq Scan to a Bitmap Index Scan feeding a Bitmap Heap Scan, and disk block reads fell from 233,493 to 79.

### 3.3 Q3 Merchant Net Settlement

```diff
- Hash Join + Seq Scan                           4,445.1 ms   240,507 disk blocks
+ Merge Join (Index Only + Index Scan)           1,647.4 ms    30,385 disk blocks
```

The `INCLUDE (amount, fee_amount, currency)` clause stores the payload columns in the leaf pages, so the executor can read much of the projection from the index rather than the heap. The gain here is the smallest of the three queries: disk reads fell from 240,507 to 30,385 blocks and the runtime from 4,445.1 ms to 1,647.4 ms (2.7x). The query aggregates a full day of settled transactions, and the planner retained a merge join, so the covering index reduced heap traffic without removing the day-range scan.

---

## 4. Execution Procedure

```bash
# 1. Create the database and apply the schema
psql -U postgres -c "CREATE DATABASE apexpay_db;"
psql -U postgres -d apexpay_db -f ../portfolio-1-database-design/01_schema_ddl.sql

# 2. Generate the synthetic dataset
#    2.45M customers, 3.1M accounts, 14.2M transactions, 28.4M ledger entries
psql -U postgres -d apexpay_db -f 04_synthetic_data_generator.sql

# 3. Capture the baseline plans BEFORE any index exists
psql -U postgres -d apexpay_db -f 01_advanced_queries.sql -o plans_baseline.txt

# 4. Create the supporting indexes
psql -U postgres -d apexpay_db -f 05_index_creation.sql

# 5. Re-run the queries and compare plan shape and buffer counts
psql -U postgres -d apexpay_db -f 01_advanced_queries.sql -o plans_indexed.txt
```

> [!WARNING]
> Baseline plans must be captured before the indexes are created. Once the indexes exist the sequential scan plans recorded in `02_execution_plans.json` cannot be reproduced without dropping them again.

> [!NOTE]
> Index maintenance is not free. Additional indexes on `transactions` reduced write throughput by roughly 22% through auxiliary B-Tree maintenance, which is why the partial and covering forms were preferred over a full composite index.
