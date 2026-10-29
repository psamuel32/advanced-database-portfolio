# Concurrency Control, Isolation Levels & Deadlock Resolution

## 1. Concurrency Phenomena Matrix (ANSI SQL-92 vs PostgreSQL)

| Phenomenon | ANSI SQL-92 Definition | PostgreSQL READ COMMITTED | PostgreSQL REPEATABLE READ | PostgreSQL SERIALIZABLE |
| :--- | :--- | :---: | :---: | :---: |
| **Dirty Read (G1)** | Reading uncommitted updates from another transaction that later rolls back. | **Prevented** (MVCC `xmin` visibility) | **Prevented** | **Prevented** |
| **Non-Repeatable Read** | Rereading a row and observing values updated by another committed transaction. | Possible | **Prevented** (Snapshot fixed at statement 1) | **Prevented** |
| **Phantom Read** | Re-executing a range scan and observing new qualifying rows inserted by others. | Possible | **Prevented** (PostgreSQL prevents phantoms in RR) | **Prevented** |
| **Serialization Anomaly** | Interleaved execution producing outcomes impossible under any serial ordering. | Possible | Possible (e.g. Write Skew) | **Prevented** (SSI Predicate Locks) |

---

## 2. Multiversion Concurrency Control (MVCC) Internals
PostgreSQL does not block readers with writers:
- Every table tuple contains system headers: `xmin` (creating transaction ID) and `xmax` (deleting/updating transaction ID).
- When an account balance is updated, PostgreSQL does not overwrite the row in place. It marks the existing row with `xmax = current_xid` and inserts a new physical tuple with `xmin = current_xid`.
- Concurrent readers inspect their snapshot transaction active list to decide whether to read the old or new tuple version.

---

## 3. Deadlock Prevention Strategy (Strict Lock Ordering)

### The Deadlock Scenario
- Transaction 1 transfers money from Account A to Account B (`LOCK A`, then requests `LOCK B`).
- Transaction 2 simultaneously transfers money from Account B to Account A (`LOCK B`, then requests `LOCK A`).
- Both sessions deadlock in cyclic wait.

### Resolution Implemented in ApexPay:
We enforce a global canonical ordering rule across all multi-account procedures:
```sql
-- Always acquire row locks in lexicographical / ascending UUID order
SELECT balance FROM accounts 
WHERE account_id IN (acc_from, acc_to)
ORDER BY account_id ASC
FOR UPDATE;
```
Because the statement above requests both row locks in a single ascending pass, every transaction acquires its locks in the same relative order. A cyclic wait graph therefore cannot form, so deadlock resolution is structural rather than reactive, and no retry loop is required.
