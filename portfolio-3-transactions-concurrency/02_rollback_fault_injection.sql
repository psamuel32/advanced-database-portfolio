-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 3
-- INVARIANT FAULT INJECTION & SAVEPOINT ROLLBACK VERIFICATION
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 1: Read and Lock Alice Account (cleared balance is well below the requested debit)
SELECT account_id, balance 
FROM accounts 
WHERE account_id = 'a1000000-0000-0000-0000-000000000001' 
FOR UPDATE;

-- Step 2: Open a savepoint so the failed debit can be isolated
SAVEPOINT before_debit;

-- Step 3: Fault Injection — Attempt transfer exceeding funds ($1,200.00 debit)
-- Expected Behavior: Database trips CHECK (balance >= 0) constraint
UPDATE accounts 
SET balance = balance - 1200.0000 
WHERE account_id = 'a1000000-0000-0000-0000-000000000001';

-- [DATABASE KERNEL INTERRUPTS: ERROR 23514 check_violation: accounts_balance_check]
-- The transaction is now in the aborted state. Until it is cleared, PostgreSQL
-- accepts only ROLLBACK, ROLLBACK TO SAVEPOINT and COMMIT.

-- Step 4: Roll back only the failed debit, leaving the transaction usable
ROLLBACK TO SAVEPOINT before_debit;

-- Step 5: Verification Query — Confirm zero state drift
SELECT account_id, balance, updated_at 
FROM accounts 
WHERE account_id = 'a1000000-0000-0000-0000-000000000001';

-- Step 6: Close the transaction cleanly. The failed debit is discarded while
-- any work performed before the savepoint is retained.
COMMIT;
