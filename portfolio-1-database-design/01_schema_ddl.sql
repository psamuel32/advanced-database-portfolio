-- =====================================================================
-- MIT 8103 ADVANCED DATABASE SYSTEMS: PRACTICAL PORTFOLIO 1
-- CASE STUDY: APEXPAY GLOBAL FINANCIAL PLATFORM
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
-- DEGREE: Master of Information Technology | MIVA Open University
-- =====================================================================

-- 0. EXTENSIONS & PREREQUISITES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Clean teardown for reproducible setup
DROP TABLE IF EXISTS fraud_alerts CASCADE;
DROP TABLE IF EXISTS ledger_entries CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS cards CASCADE;
DROP TABLE IF EXISTS merchants CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- 1. CUSTOMERS TABLE (1NF -> 3NF / BCNF Compliant)
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    phone_number VARCHAR(32) NOT NULL UNIQUE,
    full_name VARCHAR(128) NOT NULL,
    kyc_tier SMALLINT NOT NULL DEFAULT 1 CHECK (kyc_tier BETWEEN 1 AND 3),
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE' 
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'FROZEN', 'PENDING_REVIEW')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. ACCOUNTS & MULTI-CURRENCY WALLETS
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    account_number VARCHAR(16) NOT NULL UNIQUE,
    currency CHAR(3) NOT NULL CHECK (currency IN ('NGN', 'USD', 'EUR', 'GBP')),
    account_type VARCHAR(32) NOT NULL DEFAULT 'CHECKING'
        CHECK (account_type IN ('CHECKING', 'SAVINGS', 'ESCROW', 'MERCHANT_SETTLEMENT')),
    balance NUMERIC(18, 4) NOT NULL DEFAULT 0.0000 CHECK (balance >= 0),
    ledger_balance NUMERIC(18, 4) NOT NULL DEFAULT 0.0000,
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'DORMANT', 'BLOCKED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. TRANSACTIONS AUTHORIZATION TABLE
CREATE TABLE transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    dest_account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    amount NUMERIC(18, 4) NOT NULL CHECK (amount > 0),
    fee_amount NUMERIC(18, 4) NOT NULL DEFAULT 0.0000 CHECK (fee_amount >= 0),
    currency CHAR(3) NOT NULL,
    transaction_type VARCHAR(32) NOT NULL
        CHECK (transaction_type IN ('P2P_TRANSFER', 'BILL_PAY', 'POS_PURCHASE', 'CARD_PAYMENT', 'REVERSAL')),
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'SETTLED', 'FAILED', 'REVERSED')),
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. IMMUTABLE DOUBLE-ENTRY LEDGER TABLE
CREATE TABLE ledger_entries (
    entry_id BIGSERIAL PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    entry_type VARCHAR(10) NOT NULL CHECK (entry_type IN ('DEBIT', 'CREDIT')),
    amount NUMERIC(18, 4) NOT NULL CHECK (amount > 0),
    running_balance NUMERIC(18, 4) NOT NULL,
    posted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 5. MERCHANTS REGISTER
CREATE TABLE merchants (
    merchant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL UNIQUE REFERENCES customers(customer_id) ON DELETE RESTRICT,
    business_name VARCHAR(255) NOT NULL,
    merchant_category_code CHAR(4) NOT NULL,
    settlement_account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    settlement_schedule VARCHAR(16) NOT NULL DEFAULT 'INSTANT'
        CHECK (settlement_schedule IN ('INSTANT', 'T_PLUS_1', 'T_PLUS_3')),
    fee_tier_pct NUMERIC(5, 3) NOT NULL DEFAULT 0.015 CHECK (fee_tier_pct >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 6. PAYMENT CARDS (PCI-DSS TOKENIZED)
CREATE TABLE cards (
    card_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    card_token VARCHAR(128) NOT NULL UNIQUE,
    masked_pan VARCHAR(20) NOT NULL,
    expiry_month SMALLINT NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year SMALLINT NOT NULL CHECK (expiry_year >= 2026),
    card_type VARCHAR(16) NOT NULL CHECK (card_type IN ('VIRTUAL', 'PHYSICAL')),
    daily_limit NUMERIC(18, 4) NOT NULL DEFAULT 500000.0000 CHECK (daily_limit > 0),
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'BLOCKED', 'EXPIRED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 7. FRAUD RISK MONITORING ALERTS
CREATE TABLE fraud_alerts (
    alert_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    risk_score NUMERIC(5, 2) NOT NULL CHECK (risk_score BETWEEN 0.00 AND 100.00),
    rule_triggered VARCHAR(128) NOT NULL,
    action_taken VARCHAR(32) NOT NULL DEFAULT 'ALLOW'
        CHECK (action_taken IN ('ALLOW', 'STEP_UP_2FA', 'HARD_BLOCK', 'MANUAL_REVIEW')),
    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- AUTOMATED TIMESTAMP REFRESH TRIGGER
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_timestamp_customers
BEFORE UPDATE ON customers
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TRIGGER set_timestamp_accounts
BEFORE UPDATE ON accounts
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
