-- =====================================================================
-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 2
-- SYNTHETIC DATASET GENERATOR
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
--
-- PURPOSE
--   Produces the dataset that the benchmarks in this folder were measured
--   against. Run this AFTER portfolio-1-database-design/01_schema_ddl.sql
--   and BEFORE any EXPLAIN ANALYZE capture.
--
-- TARGET CARDINALITIES (see benchmark_metadata in 02_execution_plans.json)
--   customers          2,450,000
--   accounts           3,100,000
--   transactions      14,200,000
--   ledger_entries    28,400,000   (2 postings per transaction)
--   merchants            120,000
--   fraud_alerts     approx 142,000
--   cards              not populated (no Portfolio 2 query reads it)
--
-- NOTE
--   Generation writes tens of millions of rows and will take several
--   minutes. Set maintenance_work_mem generously before running.
--   ANALYZE is executed at the end so the planner has accurate statistics;
--   without it the baseline plans will not resemble the captured ones.
-- =====================================================================

TRUNCATE TABLE
    fraud_alerts,
    ledger_entries,
    transactions,
    cards,
    merchants,
    accounts,
    customers
RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------
-- 1. CUSTOMERS: 2,450,000
-- ---------------------------------------------------------------------
INSERT INTO customers (customer_id, email, phone_number, full_name, kyc_tier, status)
SELECT
    ('c1000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
    'customer' || i || '@apexpay.test',
    '+234' || lpad(i::text, 10, '0'),
    'Customer ' || i,
    ((i % 3) + 1)::smallint,
    CASE WHEN i % 97 = 0 THEN 'SUSPENDED' ELSE 'ACTIVE' END
FROM generate_series(1, 2450000) AS s(i);

-- ---------------------------------------------------------------------
-- 2. ACCOUNTS: 3,100,000
--    Every fifth account is a merchant settlement account, which is the
--    join path query 3 uses to reach a merchant from a transaction.
-- ---------------------------------------------------------------------
INSERT INTO accounts (account_id, customer_id, account_number, currency, account_type, balance, ledger_balance, status)
SELECT
    ('a1000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
    ('c1000000-0000-0000-0000-' || lpad((((i - 1) % 2450000) + 1)::text, 12, '0'))::uuid,
    lpad((1000000000 + i)::text, 10, '0'),
    (ARRAY['NGN', 'USD', 'EUR', 'GBP'])[(i % 4) + 1],
    CASE WHEN i % 5 = 0 THEN 'MERCHANT_SETTLEMENT' ELSE 'CHECKING' END,
    ((i % 50000) + 1000)::numeric(18, 4),
    ((i % 50000) + 1000)::numeric(18, 4),
    'ACTIVE'
FROM generate_series(1, 3100000) AS s(i);

-- ---------------------------------------------------------------------
-- 3. MERCHANTS: 120,000
--    Merchant n is bound to account 5n, guaranteeing that
--    accounts.account_type = 'MERCHANT_SETTLEMENT' for every merchant.
-- ---------------------------------------------------------------------
INSERT INTO merchants (merchant_id, customer_id, business_name, merchant_category_code, settlement_account_id, settlement_schedule, fee_tier_pct)
SELECT
    ('e1000000-0000-0000-0000-' || lpad(r::text, 12, '0'))::uuid,
    ('c1000000-0000-0000-0000-' || lpad((((r * 5) - 1) % 2450000 + 1)::text, 12, '0'))::uuid,
    'Merchant Enterprise ' || r,
    lpad(((r % 9000) + 1000)::text, 4, '0'),
    ('a1000000-0000-0000-0000-' || lpad((r * 5)::text, 12, '0'))::uuid,
    (ARRAY['INSTANT', 'T_PLUS_1', 'T_PLUS_3'])[(r % 3) + 1],
    (0.010 + ((r % 5) * 0.005))::numeric(5, 3)
FROM generate_series(1, 120000) AS s(r);

-- ---------------------------------------------------------------------
-- 4. TRANSACTIONS: 14,180,000 base rows
--    created_at is spread across the trailing 30 days. Step 7 then adds a
--    20,000-row live activity burst stamped with clock_timestamp(), so the
--    transaction total is exactly 14,200,000. Only SETTLED and PENDING rows
--    are produced, so every transaction posts exactly two ledger entries
--    (28,400,000 total).
-- ---------------------------------------------------------------------
INSERT INTO transactions (transaction_id, source_account_id, dest_account_id, amount, fee_amount, currency, transaction_type, status, idempotency_key, created_at)
SELECT
    ('b1000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
    ('a1000000-0000-0000-0000-' || lpad((((i * 3) % 3100000) + 1)::text, 12, '0'))::uuid,
    ('a1000000-0000-0000-0000-' || lpad((((i * 7) % 3100000) + 1)::text, 12, '0'))::uuid,
    ((i % 99000) + 1000)::numeric(18, 4),
    ROUND((((i % 99000) + 1000) * 0.005)::numeric, 4)::numeric(18, 4),
    (ARRAY['NGN', 'USD', 'EUR', 'GBP'])[(i % 4) + 1],
    (ARRAY['P2P_TRANSFER', 'CARD_PAYMENT', 'POS_PURCHASE', 'BILL_PAY'])[(i % 4) + 1],
    CASE WHEN (i % 10) = 0 THEN 'PENDING' ELSE 'SETTLED' END,
    'idem-' || i,
    NOW() - ((i % 2592000)::text || ' seconds')::interval
FROM generate_series(1, 14180000) AS s(i);

-- ---------------------------------------------------------------------
-- 5. LEDGER ENTRIES: 28,400,000
--    Two immutable postings per transaction: one DEBIT against the
--    source account, one CREDIT against the destination account.
--    running_balance is written as 0 here; the reconciliation query
--    recomputes it from the entry stream rather than trusting the column.
-- ---------------------------------------------------------------------
INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, running_balance, posted_at)
SELECT
    t.transaction_id,
    t.source_account_id,
    'DEBIT',
    t.amount + t.fee_amount,
    0,
    t.created_at
FROM transactions t;

INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, running_balance, posted_at)
SELECT
    t.transaction_id,
    t.dest_account_id,
    'CREDIT',
    t.amount,
    0,
    t.created_at
FROM transactions t;

-- ---------------------------------------------------------------------
-- 6. FRAUD ALERTS: high-value sample used by the query 2 left join
-- ---------------------------------------------------------------------
INSERT INTO fraud_alerts (alert_id, transaction_id, risk_score, rule_triggered, action_taken, detected_at)
SELECT
    ('f1000000-0000-0000-0000-' || lpad((row_number() OVER ())::text, 12, '0'))::uuid,
    ('b1000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
    (i % 100)::numeric(5, 2),
    (ARRAY['VELOCITY_5MIN', 'GEO_MISMATCH', 'TOR_EXIT_NODE', 'CARD_TESTING'])[(i % 4) + 1],
    'ALLOW',
    NOW() - ((i % 2592000)::text || ' seconds')::interval
FROM generate_series(1, 14180000) AS s(i)
WHERE ((i % 99000) + 1000) >= 50000
  AND (i % 50) = 0;

-- ---------------------------------------------------------------------
-- 7. LIVE ACTIVITY BURST
--    The base transaction stream is spread across 30 days, so any short
--    trailing window contains almost no repeated activity from a single
--    account. Query 2 looks for accounts making 3+ high-value transfers in
--    a trailing window, so without recent, concentrated activity its result
--    set would be empty.
--
--    This block creates a dense cluster of recent high-value transfers from a
--    small set of 200 accounts, stamped with clock_timestamp() at the very end
--    of generation. The queries are captured a few minutes later, so the burst
--    is still inside the trailing window at capture time. It also keeps the
--    transaction total at exactly 14.2 million (14,180,000 + 20,000).
-- ---------------------------------------------------------------------
INSERT INTO transactions (transaction_id, source_account_id, dest_account_id, amount, fee_amount, currency, transaction_type, status, idempotency_key, created_at)
SELECT
    ('b2000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
    ('a1000000-0000-0000-0000-' || lpad((((i - 1) % 200) + 1)::text, 12, '0'))::uuid,
    ('a1000000-0000-0000-0000-' || lpad(((((i - 1) % 200)) + 101)::text, 12, '0'))::uuid,
    ((i % 40000) + 60000)::numeric(18, 4),
    ROUND((((i % 40000) + 60000) * 0.005)::numeric, 4)::numeric(18, 4),
    'NGN',
    CASE WHEN i % 2 = 0 THEN 'P2P_TRANSFER' ELSE 'CARD_PAYMENT' END,
    'SETTLED',
    'live-' || i,
    clock_timestamp() - ((i % 240) * INTERVAL '1 second')
FROM generate_series(1, 20000) AS s(i);

INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, running_balance, posted_at)
SELECT t.transaction_id, t.source_account_id, 'DEBIT', t.amount + t.fee_amount, 0, t.created_at
FROM transactions t
WHERE t.idempotency_key LIKE 'live-%';

INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, running_balance, posted_at)
SELECT t.transaction_id, t.dest_account_id, 'CREDIT', t.amount, 0, t.created_at
FROM transactions t
WHERE t.idempotency_key LIKE 'live-%';

-- ---------------------------------------------------------------------
-- 8. Planner statistics. Required for the baseline plans to match.
-- ---------------------------------------------------------------------
ANALYZE customers;
ANALYZE accounts;
ANALYZE merchants;
ANALYZE transactions;
ANALYZE ledger_entries;
ANALYZE fraud_alerts;
