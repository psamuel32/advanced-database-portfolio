-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 2
-- COMPLEX ANALYTICAL & OPERATIONAL SQL QUERIES
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)

-- =====================================================================
-- QUERY 1: RUNNING BALANCE RECONCILIATION & VARIANCE AUDIT
-- Business Goal: Validate that cumulative debit/credit journal entries
-- match the cleared account snapshot balance with 0 variance.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)
WITH account_ledger_flow AS (
    SELECT 
        l.entry_id,
        l.account_id,
        a.account_number,
        c.full_name AS customer_name,
        l.entry_type,
        l.amount,
        CASE 
            WHEN l.entry_type = 'CREDIT' THEN l.amount
            WHEN l.entry_type = 'DEBIT'  THEN -l.amount
        END AS net_flow,
        l.posted_at,
        SUM(CASE 
            WHEN l.entry_type = 'CREDIT' THEN l.amount
            WHEN l.entry_type = 'DEBIT'  THEN -l.amount
        END) OVER (
            PARTITION BY l.account_id 
            ORDER BY l.posted_at ASC, l.entry_id ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS computed_running_balance,
        a.balance AS snapshot_cleared_balance
    FROM ledger_entries l
    JOIN accounts a ON l.account_id = a.account_id
    JOIN customers c ON a.customer_id = c.customer_id
    WHERE l.account_id = 'a1000000-0000-0000-0000-000000000001'
)
SELECT 
    entry_id,
    account_number,
    customer_name,
    entry_type,
    amount,
    computed_running_balance,
    snapshot_cleared_balance,
    (snapshot_cleared_balance - computed_running_balance) AS reconciliation_variance,
    posted_at
FROM account_ledger_flow
ORDER BY posted_at DESC
LIMIT 10;

-- =====================================================================
-- QUERY 2: 30-MINUTE SLIDING WINDOW FRAUD VELOCITY SURVEILLANCE
-- Business Goal: Flag accounts conducting 3+ high-value transfers
-- within 1800 seconds to preempt smurfing and card takeover attacks.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)
SELECT 
    t.source_account_id,
    c.full_name AS customer_name,
    c.phone_number,
    COUNT(t.transaction_id) AS transfer_count_30min,
    SUM(t.amount) AS total_volume_outflow,
    AVG(f.risk_score) AS avg_fraud_score,
    MAX(t.created_at) - MIN(t.created_at) AS time_span_interval,
    DENSE_RANK() OVER (ORDER BY SUM(t.amount) DESC) AS risk_rank
FROM transactions t
JOIN accounts a ON t.source_account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
LEFT JOIN fraud_alerts f ON t.transaction_id = f.transaction_id
WHERE t.created_at >= NOW() - INTERVAL '30 minutes'
  AND t.transaction_type IN ('P2P_TRANSFER', 'CARD_PAYMENT')
  AND t.amount >= 50000.0000
GROUP BY t.source_account_id, c.full_name, c.phone_number
HAVING COUNT(t.transaction_id) >= 3
ORDER BY total_volume_outflow DESC;

-- =====================================================================
-- QUERY 3: END-OF-DAY MERCHANT BATCH SETTLEMENT & FEE DISBURSEMENT
-- Business Goal: Aggregate cleared sales, compute contract interchange
-- cuts, and prepare net disbursement files for automated clearing.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)
SELECT 
    m.merchant_id,
    m.business_name,
    m.merchant_category_code AS mcc,
    m.settlement_schedule,
    t.currency,
    COUNT(t.transaction_id) AS total_settled_orders,
    SUM(t.amount) AS gross_sales_volume,
    SUM(t.fee_amount) AS total_platform_interchange_fees,
    (SUM(t.amount) - SUM(t.fee_amount)) AS net_disbursement_payable,
    ROUND(AVG(t.amount), 2) AS average_ticket_size
FROM merchants m
JOIN accounts a ON m.settlement_account_id = a.account_id
JOIN transactions t ON t.dest_account_id = a.account_id
WHERE t.status = 'SETTLED'
  AND t.created_at >= CURRENT_DATE - INTERVAL '1 day'
GROUP BY 
    m.merchant_id, 
    m.business_name, 
    m.merchant_category_code, 
    m.settlement_schedule, 
    t.currency
HAVING SUM(t.amount) > 10000.0000
ORDER BY gross_sales_volume DESC;
