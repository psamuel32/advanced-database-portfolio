# Mathematical Normalisation Analysis (UNF to BCNF)

## 1. Unnormalised Form (UNF)
The legacy reporting schema exported data in a flat table containing repeating groups and nested multi-valued attributes:

```
R_UNF = {Tx_Ref, Cust_Name, Cust_Email, Phone, KYC_Tier, {Acc_Num, Cur, Bal}, Dest_Acc, {Tx_Amount, Tx_Type}, Merchant_Name}
```

**Anomalies Present:**
- *Insertion Anomaly:* Cannot record a new customer before they open an account and perform a transaction.
- *Deletion Anomaly:* Deleting a cancelled transaction purges the customer record if it was their sole transaction.
- *Update Anomaly:* Updating a phone number requires scanning millions of redundant transaction rows.

---

## 2. First Normal Form (1NF)
**Condition:** All attribute values must be atomic (no repeating groups, comma-separated lists, or nested relations).

**Decomposition:**
We unnest repeating arrays and identify the candidate key `{transaction_id, account_id, entry_seq}`.

```
R_1NF = {transaction_id, account_id, entry_seq, customer_name, customer_email, phone, kyc_tier, currency, balance, tx_amount, fee_amount, tx_type, tx_status}
```

**Functional Dependencies (FDs) in 1NF:**
- FD1: {transaction_id, account_id, entry_seq} -> R (Primary Key)
- FD2: {account_id} -> {customer_name, customer_email, phone, kyc_tier, currency, balance}
- FD3: {transaction_id} -> {tx_amount, fee_amount, tx_type, tx_status}

**Defect:** FD2 and FD3 are partial dependencies, where non-prime attributes depend on only a subset of the candidate key.

---

## 3. Second Normal Form (2NF)
**Condition:** Relation must be in 1NF AND every non-prime attribute must be fully functionally dependent on the entire primary key (no partial dependencies).

**Decomposition into 3 Relations:**
1. `CUSTOMER_ACCOUNTS(account_id, customer_name, customer_email, phone, kyc_tier, currency, balance)`
2. `TRANSACTIONS(transaction_id, source_account_id, dest_account_id, tx_amount, fee_amount, tx_status)`
3. `LEDGER_ENTRIES(entry_id, transaction_id, account_id, entry_type, amount, running_balance)`

**Defect:** In `CUSTOMER_ACCOUNTS`, transitive functional dependencies exist:
- `account_id -> customer_email`
- `customer_email -> {customer_name, phone, kyc_tier}`

---

## 4. Third Normal Form (3NF)
**Condition:** Relation must be in 2NF AND no non-prime attribute is transitively dependent on the candidate key. Formally, for every non-trivial dependency X -> Y:
1. X is a superkey, OR
2. Y is a prime attribute (a member of a candidate key).

**Decomposition:**
Extract customer identity into a dedicated `CUSTOMERS` table:
- `CUSTOMERS(customer_id, email, phone_number, full_name, kyc_tier, status)`
- `ACCOUNTS(account_id, customer_id, account_number, currency, account_type, balance, status)`

Now, all non-prime attributes depend directly and solely on their respective relation's candidate key.

---

## 5. Boyce-Codd Normal Form (BCNF)
**Condition:** A relation is in BCNF if and only if for every non-trivial functional dependency X -> Y, X is a strict superkey.

### Determinant Verification Matrix:
| Relation | Functional Dependency (X -> Y) | Determinant (X) Status | BCNF Compliance |
| :--- | :--- | :--- | :--- |
| **CUSTOMERS** | `customer_id -> {email, phone, name, kyc}` | Candidate Superkey | **YES** |
| **CUSTOMERS** | `email -> {customer_id, phone, name, kyc}` | Alternate Superkey | **YES** |
| **CUSTOMERS** | `phone_number -> {customer_id, email, ...}` | Alternate Superkey | **YES** |
| **ACCOUNTS** | `account_id -> {customer_id, number, bal}` | Candidate Superkey | **YES** |
| **ACCOUNTS** | `account_number -> {account_id, customer_id}` | Alternate Superkey | **YES** |
| **TRANSACTIONS** | `transaction_id -> {source, dest, amount}` | Candidate Superkey | **YES** |
| **TRANSACTIONS** | `idempotency_key -> {transaction_id, ...}` | Alternate Superkey | **YES** |
| **LEDGER_ENTRIES** | `entry_id -> {transaction_id, account, ...}` | Candidate Superkey | **YES** |

**Conclusion:** Every determinant across all relations is a candidate superkey. The schema satisfies BCNF with zero dependency loss and zero redundant data storage.

> [!NOTE]
> The BCNF verification for `CUSTOMERS` treats `email` and `phone_number` as alternate candidate keys. Both are declared `UNIQUE NOT NULL` in `01_schema_ddl.sql`, so each determines the whole tuple and the relation remains in BCNF.
