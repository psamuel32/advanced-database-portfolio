# Portfolio 1: Database Design and Relational Modelling

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Relations](https://img.shields.io/badge/relations-7-informational)
![Normalisation](https://img.shields.io/badge/normalisation-BCNF-success)

Author: Praise Samuel (p.okoro4197@miva.edu.ng)

---

## 1. Objective and Deliverables

This directory contains the complete relational design for the ApexPay Global case study:
1. Entity relationship model with a full attribute dictionary and Crow's foot cardinality notation.
2. Production PostgreSQL DDL (`01_schema_ddl.sql`) defining primary keys, foreign keys, unique constraints, domain check rules and update triggers.
3. Step-by-step normalisation proof from Unnormalised Form (UNF) through 1NF, 2NF and 3NF to Boyce-Codd Normal Form (BCNF).

```diff
- Denormalised reporting export carrying repeating customer and account groups (UNF)
+ Seven relations normalised to BCNF: customers, accounts, transactions,
+ ledger_entries, merchants, cards, fraud_alerts
```

---

## 2. Relational Architecture

| Relation | Purpose | Principal Constraints |
| :--- | :--- | :--- |
| `customers` | Identity registry for retail and merchant account holders | Unique email and phone; KYC tier flags (Tiers 1–3) |
| `accounts` | Multi-currency deposit accounts (NGN, USD, EUR, GBP) | `CHECK (balance >= 0)`; foreign key to `customers` |
| `transactions` | Authorisation parent record for each payment attempt | Stores source, destination, fee, idempotency key and status |
| `ledger_entries` | Immutable double-entry bookkeeping journal | Balanced DEBIT and CREDIT postings |
| `merchants` | Registered commercial enterprises | Linked to settlement accounts and interchange fee schedules |
| `cards` | Tokenised payment card credentials | Linked to funding accounts with daily limits |
| `fraud_alerts` | Risk scores and triggered rules | Inference score recorded per transaction |

> [!NOTE]
> UUIDv4 surrogate keys are used in place of sequential integers throughout. This prevents identifier enumeration and permits collision-free record creation across independent shards.

---

## 3. Execution and Verification

```bash
# Create the database and apply the schema
psql -U postgres -c "CREATE DATABASE apexpay_db;"
psql -U postgres -d apexpay_db -f 01_schema_ddl.sql

# Verify table creation and inspect the resulting constraints
psql -U postgres -d apexpay_db -c "\dt"
psql -U postgres -d apexpay_db -c "\d accounts"
```

> [!IMPORTANT]
> The `uuid-ossp` and `pgcrypto` extensions must be available before the DDL is applied. Because the script creates both extensions, the executing role requires superuser or equivalent privileges.

---

## 4. Design Decisions

- UUID surrogate keys: UUIDv4 identifiers prevent enumeration of account and customer records and allow records to be created independently on separate shards without coordination.
- Restricted foreign keys: `ON DELETE RESTRICT` on `accounts` and `customers` prevents orphaned balance records, which would otherwise corrupt ledger reconciliation.
- Domain balance conservation: the balance attribute carries `CHECK (balance >= 0)` at the database kernel level, so a negative balance cannot be committed even if an application-level check is bypassed.
