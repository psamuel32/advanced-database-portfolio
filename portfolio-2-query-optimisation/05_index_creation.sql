-- =====================================================================
-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 2
-- INDEX CREATION SCRIPT
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
--
-- RUN ORDER MATTERS
--   1. 01_advanced_queries.sql        -> capture the baseline plans
--   2. this script                    -> create the supporting indexes
--   3. 01_advanced_queries.sql        -> capture the indexed plans
--
-- Once these indexes exist, the sequential scan baselines recorded in
-- 02_execution_plans.json cannot be reproduced until the indexes are
-- dropped again. The DROP statements below make the script re-runnable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Query 1: composite ordering matching the window specification
--   PARTITION BY account_id ORDER BY posted_at ASC, entry_id ASC
-- Reading B-Tree leaves in sorted order removes the explicit sort node.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_ledger_acc_posted;

CREATE INDEX idx_ledger_acc_posted
    ON ledger_entries (account_id, posted_at ASC, entry_id ASC);

-- ---------------------------------------------------------------------
-- Query 2: partial index on high-value customer-initiated transfers
--   The predicate mirrors the query predicate exactly. PostgreSQL will
--   only select a partial index when the query predicate implies it.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_tx_velocity_partial;

CREATE INDEX idx_tx_velocity_partial
    ON transactions (created_at DESC, amount)
    WHERE transaction_type IN ('P2P_TRANSFER', 'CARD_PAYMENT')
      AND amount >= 50000.0000;

-- ---------------------------------------------------------------------
-- Query 3: covering index enabling an Index Only Scan
--   The INCLUDE payload stores the aggregated columns in the leaf pages,
--   so the settlement aggregation never reads heap pages.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_tx_dest_status_date;

CREATE INDEX idx_tx_dest_status_date
    ON transactions (dest_account_id, status, created_at)
    INCLUDE (amount, fee_amount, currency);

-- ---------------------------------------------------------------------
-- Refresh statistics so the planner can cost the new paths accurately.
-- ---------------------------------------------------------------------
ANALYZE ledger_entries;
ANALYZE transactions;
