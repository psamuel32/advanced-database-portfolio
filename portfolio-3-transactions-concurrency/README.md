# Portfolio 3: Transactions and Concurrency Control

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Isolation](https://img.shields.io/badge/isolation-MVCC%20and%202PL-blue)
![Tests](https://img.shields.io/badge/transaction%20tests-3-informational)

Author: Praise Samuel (p.okoro4197@miva.edu.ng)

---

## 1. Scope of Work

This directory documents the transaction processing and concurrency behaviour of ApexPay Global:
1. An atomic multi-row transfer that preserves ledger conservation (commit path).
2. A fault injection test that provokes constraint rejection and requires state reversion (rollback path).
3. A study of ANSI SQL-92 isolation levels, PostgreSQL Multiversion Concurrency Control (MVCC) visibility, and two-phase locking (2PL) ordering.

---

## 2. Transfer Semantics

```diff
  BEGIN;
-   Read balances without locking; concurrent writers can interleave freely
+   SELECT balance FROM accounts WHERE account_id = ... FOR UPDATE;   -- row-level exclusive lock
    UPDATE accounts SET balance = balance - 502.50 WHERE account_id = ...;   -- debit sender
+   UPDATE accounts SET balance = balance + 500.00 WHERE account_id = ...;   -- credit recipient
+   UPDATE accounts SET balance = balance +   2.50 WHERE account_id = ...;   -- credit fee revenue
+   INSERT INTO ledger_entries ...                                          -- 3 balanced postings
  COMMIT;
```

The `FOR UPDATE` clause acquires row-level exclusive locks on every account touched by the transfer. Committing flushes the write-ahead log to disk through a synchronous `fsync`, which is what makes the zero-loss guarantee possible at the cost of a network round trip.

> [!NOTE]
> Lock ordering follows ascending `account_id`. Because every transaction acquires locks in the same canonical order, cyclic wait conditions cannot form and deadlocks are eliminated deterministically.

---

## 3. Test Procedures

### 3.1 Committed Transfer

```bash
psql -U postgres -d apexpay_db -f 01_acid_transfer_commit.sql
```

Expected result: the sender is debited 502.50, the recipient is credited 500.00, the fee revenue account is credited 2.50, and exactly three balanced ledger entries are posted.

### 3.2 Overdraft Fault Injection

```bash
psql -U postgres -d apexpay_db -f 02_rollback_fault_injection.sql
```

Expected result: the transfer is rejected before the balance becomes negative.

```diff
- Sender balance well below the 1,200.00 debit being attempted
+ ERROR 23514: check_violation (accounts_balance_check)  ->  ROLLBACK TO SAVEPOINT
```

The script opens a savepoint ahead of the debit, so the rejection discards only that statement and the enclosing transaction is then committed cleanly. This is the recovery path that a real service would use, rather than discarding the whole transaction.

> [!WARNING]
> This script is expected to raise an exception. The error is the assertion being tested, so a run that completes silently would indicate that the constraint is missing.

### 3.3 Concurrent Interleaving and Deadlock Tests

Open two independent sessions and apply the step-by-step interleavings documented in `03_isolation_concurrency_study.md`. Each step lists the statement to run in the first session, the statement to run in the second, and the lock state that should be observable between them.

---

## 4. Isolation Analysis

The study evaluates dirty reads, non-repeatable reads and lost updates against the ANSI SQL-92 levels, and verifies each observed behaviour against PostgreSQL's MVCC tuple visibility rules (`xmin` and `xmax`). The practical conclusion is that read-committed isolation is sufficient for balance lookups, while the transfer path requires explicit pessimistic locking because MVCC alone does not prevent lost updates on read-modify-write sequences.
