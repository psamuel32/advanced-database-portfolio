# Indexing Benchmarks & Query Optimisation Analysis

## 1. Quantitative Benchmark Summary
Measurements were captured with `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)` across 28.4 million ledger rows and 14.2 million transactions. Latencies and block counts are the root-node totals from `evidence/p2_plans_baseline.txt` (before any supporting index existed) and `evidence/p2_plans_indexed.txt` (after `05_index_creation.sql`).

| Query ID & Focus | Baseline Plan | Baseline Latency | Optimized Plan | Optimized Latency | Speedup Multiplier | Disk Blocks Read |
| :--- | :--- | :---: | :--- | :---: | :---: | :---: |
| **Q1: Running Balance Audit** | Seq Scan (28.4M rows) | 22,766.5 ms | Index Scan (`idx_ledger_acc_posted`) | **4.19 ms** | **5,436x faster** | 347,552 → 12 |
| **Q2: Fraud Velocity Check** | Seq Scan (14.2M rows) | 3,591.9 ms | Bitmap Index Scan (`idx_tx_velocity_partial`) | **233.1 ms** | **15x faster** | 233,493 → 79 |
| **Q3: Merchant Fee Settlement** | Hash Join + Seq Scan | 4,445.1 ms | Merge Join over Index Only + Index Scan | **1,647.4 ms** | **2.7x faster** | 240,507 → 30,385 |

> [!IMPORTANT]
> These figures are the single-run wall-clock values produced by `EXPLAIN ANALYZE` on a cold cache, so the absolute baselines reflect disk reads rather than pure CPU work. The durable result is the change in plan shape and in disk blocks read; the two usually, but not always, move together, as Query 3 shows.

---

## 2. Technical Evaluation of Optimisation Strategies

### Strategy 1: Composite Ordering to Eliminate Sort Nodes (Query 1)
- **Index Applied:** `CREATE INDEX idx_ledger_acc_posted ON ledger_entries (account_id, posted_at ASC, entry_id ASC);`
- **Explanation:** The window function specifies `PARTITION BY account_id ORDER BY posted_at ASC, entry_id ASC`. By matching the index columns in exact order, PostgreSQL reads the B-Tree leaves in already sorted order, completely bypassing the in-memory quicksort node (`Sort Key: posted_at, entry_id`).

### Strategy 2: Partial Predicate Indexing (Query 2)
- **Index Applied:** `CREATE INDEX idx_tx_velocity_partial ON transactions (created_at DESC, amount) WHERE transaction_type IN ('P2P_TRANSFER', 'CARD_PAYMENT') AND amount >= 50000.0000;`
- **Explanation:** Most transactions are well below the 50,000-unit threshold, so a partial index over only high-value customer-initiated transfers (P2P and card payments) is far smaller than a full index on the table. The captured plan switched from a plain Seq Scan to a Bitmap Index Scan feeding a Bitmap Heap Scan, and disk block reads fell from 233,493 to 79 while the runtime dropped from 3,591.9 ms to 233.1 ms (15x). The predicate is written to match the query predicate exactly, because PostgreSQL only uses a partial index when the query implies the index condition.

### Strategy 3: Covering Index to Reduce Heap Fetches (Query 3)
- **Index Applied:** `CREATE INDEX idx_tx_dest_status_date ON transactions (dest_account_id, status, created_at) INCLUDE (amount, fee_amount, currency);`
- **Explanation:** The `INCLUDE` clause stores the payload columns in the leaf pages without widening the B-Tree branching structure, so the executor can satisfy much of the projection from the index instead of the heap. In the captured plan the improvement was real but modest: disk reads fell from 240,507 to 30,385 blocks and the runtime from 4,445.1 ms to 1,647.4 ms (2.7x). The settlement query still aggregates a full day of settled transactions, and the planner retained a merge join over an Index Scan on `transactions` plus a Seq Scan on the small `merchants` table, so the covering index could not remove the day-range scan. This is the clearest example in the portfolio of an index that helps without transforming the plan.
