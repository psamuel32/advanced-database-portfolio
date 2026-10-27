-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 3
-- ATOMIC FUND TRANSFER WITH DOUBLE-ENTRY LEDGER (COMMIT SCENARIO)
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)

-- Step 0: Seed the platform revenue vault (idempotent).
-- The synthetic generator numbers accounts from ...0001 upwards, so the fee
-- vault at ...0000 is created here rather than assumed to exist. Without this
-- row the fee credit and its ledger posting would fail their foreign keys.
INSERT INTO accounts (account_id, customer_id, account_number, currency, account_type, balance, ledger_balance, status)
VALUES (
    'a1000000-0000-0000-0000-000000000000',
    'c1000000-0000-0000-0000-000000000001',
    '1000000000',
    'USD',
    'ESCROW',
    1000.0000,
    1000.0000,
    'ACTIVE'
)
ON CONFLICT (account_id) DO NOTHING;

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 1: Pessimistic Row Lock on Source Account
-- Prevents race conditions, concurrent double-spends, and lost updates
SELECT account_id, balance, status 
FROM accounts 
WHERE account_id = 'a1000000-0000-0000-0000-000000000001' 
FOR UPDATE;

-- Step 2: Debit Source Account (Alice: $500.00 transfer + $2.50 processing fee)
UPDATE accounts 
SET balance = balance - 502.5000,
    updated_at = CLOCK_TIMESTAMP()
WHERE account_id = 'a1000000-0000-0000-0000-000000000001';

-- Step 3: Credit Beneficiary Account (Bob: $500.00)
UPDATE accounts 
SET balance = balance + 500.0000,
    updated_at = CLOCK_TIMESTAMP()
WHERE account_id = 'a1000000-0000-0000-0000-000000000002';

-- Step 4: Credit Platform Revenue Vault (System Fee: $2.50)
UPDATE accounts 
SET balance = balance + 2.5000,
    updated_at = CLOCK_TIMESTAMP()
WHERE account_id = 'a1000000-0000-0000-0000-000000000000';

-- Step 5: Insert Parent Authorization Record with Unique Idempotency Key
-- The transaction_id is deliberately outside the range the synthetic generator
-- emits (which uses the b1000000-... prefix) so it cannot collide with a
-- generated row and abort the transaction on a primary key violation.
INSERT INTO transactions (
    transaction_id, source_account_id, dest_account_id, amount, fee_amount, 
    currency, transaction_type, status, idempotency_key, created_at
) VALUES (
    'b1f00000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000002',
    500.0000,
    2.5000,
    'USD',
    'P2P_TRANSFER',
    'SETTLED',
    'IDEMP-2026-10-P2P-001',
    CLOCK_TIMESTAMP()
);

-- Step 6: Post Balanced Double-Entry Journal Entries
-- Sum of debits ($502.50) exactly equals sum of credits ($500.00 + $2.50)
INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, running_balance, posted_at)
VALUES 
    ('b1f00000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'DEBIT', 502.5000, 497.5000, CLOCK_TIMESTAMP()),
    ('b1f00000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'CREDIT', 500.0000, 1500.0000, CLOCK_TIMESTAMP()),
    ('b1f00000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000000', 'CREDIT', 2.5000, 52.5000, CLOCK_TIMESTAMP());

-- Step 7: Commit Transaction
-- Write-Ahead Log is synchronously flushed to persistent NVMe disk via fsync
COMMIT;
