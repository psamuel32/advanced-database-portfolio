-- =====================================================================
-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 5
-- CITUS HORIZONTAL HASH SHARDING & TEMPORAL RANGE PARTITIONS
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
-- =====================================================================

-- 1. Enable Citus Distributed Database Extension
CREATE EXTENSION IF NOT EXISTS citus;

-- 1b. Single-node bootstrap. The coordinator is registered in the metadata and
-- flagged as a node that may hold shards, which is what a one-machine Citus
-- cluster needs before any table can be distributed.
SELECT citus_set_coordinator_host('localhost', 5432);
SELECT citus_set_node_property('localhost', 5432, 'shouldhaveshards', true);

-- 1c. Citus refuses to distribute a relation that carries triggers
-- ("cannot distribute relation ... because it has triggers"). The Portfolio 1
-- DDL installs updated_at refresh triggers on customers and accounts, so they
-- are removed before distribution. In the distributed deployment updated_at is
-- maintained by the application write path instead of a per-node trigger.
DROP TRIGGER IF EXISTS set_timestamp_customers ON customers;
DROP TRIGGER IF EXISTS set_timestamp_accounts ON accounts;

-- 2. customers is a small lookup table. Citus only allows a foreign key from a
-- distributed table to a colocated distributed table or a reference table.
-- accounts.customer_id references customers.customer_id, so customers must be
-- registered as a reference table before accounts can be distributed.
SELECT create_reference_table('customers');

-- 2b. Citus cannot distribute a relation while a LOCAL table still holds a
-- foreign key pointing at it: "foreign keys from reference tables and local
-- tables to distributed tables are not supported". accounts is referenced by
-- merchants, cards, transactions and ledger_entries, so those edges are dropped
-- ahead of distribution. The ledger_entries -> accounts edge is restored in
-- step 4b once both tables are distributed and colocated; the remaining edges
-- are enforced by the application layer.
ALTER TABLE transactions   DROP CONSTRAINT IF EXISTS transactions_source_account_id_fkey;
ALTER TABLE transactions   DROP CONSTRAINT IF EXISTS transactions_dest_account_id_fkey;
ALTER TABLE ledger_entries DROP CONSTRAINT IF EXISTS ledger_entries_account_id_fkey;
ALTER TABLE ledger_entries DROP CONSTRAINT IF EXISTS ledger_entries_transaction_id_fkey;
ALTER TABLE merchants      DROP CONSTRAINT IF EXISTS merchants_settlement_account_id_fkey;
ALTER TABLE cards          DROP CONSTRAINT IF EXISTS cards_account_id_fkey;

-- 3. Horizontally Shard the Accounts Table via Hash Partitioning on account_id
-- Evenly balances 3.1 million bank accounts across the available shard nodes.
-- account_id is already the primary key, so the PK needs no change. Citus does,
-- however, require every UNIQUE constraint to include the distribution column.
-- accounts.account_number is UNIQUE on its own, so that constraint is dropped
-- before distribution; account_number uniqueness is then enforced by the
-- application layer rather than replicated across every shard.
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_account_number_key;
SELECT create_distributed_table('accounts', 'account_id', 'hash');

-- 4. Colocate Ledger Entries with Accounts
-- Citus requires the distribution column to be part of every primary key on a
-- distributed table. ledger_entries is keyed on entry_id alone, so the primary
-- key is widened to (entry_id, account_id) before distribution. Colocation
-- guarantees that an account and its ledger entries live on the exact same
-- shard, so single-account ledger reads avoid distributed two-phase commit.
ALTER TABLE ledger_entries DROP CONSTRAINT IF EXISTS ledger_entries_pkey;
ALTER TABLE ledger_entries ADD PRIMARY KEY (entry_id, account_id);
SELECT create_distributed_table('ledger_entries', 'account_id', 'hash', colocate_with => 'accounts');

-- 4b. Restore the account ledger foreign key now that both tables are
-- distributed and colocated on account_id.
ALTER TABLE ledger_entries
    ADD CONSTRAINT ledger_entries_account_id_fkey
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE RESTRICT;

-- 5. Temporal Range Partitioning on Transactions Table (Monthly Partitions)
-- transactions stays a local table; the ledger references it only by UUID, and
-- that edge is enforced by the application layer once the tables are sharded.
CREATE TABLE transactions_partitioned (
    transaction_id UUID NOT NULL,
    source_account_id UUID NOT NULL,
    dest_account_id UUID NOT NULL,
    amount NUMERIC(18, 4) NOT NULL,
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (transaction_id, created_at)
) PARTITION BY RANGE (created_at);

-- Monthly partitions with partition pruning enabled
CREATE TABLE transactions_2026_m09 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE TABLE transactions_2026_m10 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

CREATE TABLE transactions_2026_m11 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
