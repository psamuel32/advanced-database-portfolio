# High Availability SLA, RPO/RTO & PACELC Theorem Analysis

## 1. High Availability Service Level Agreement (SLA)

| Metric | Target SLA | Architecture Mechanism |
| :--- | :--- | :--- |
| **System Uptime** | **99.999% ("Five Nines")** | Patroni automatic failover + redundant standby nodes across dual zones. |
| **Recovery Point Objective (RPO)** | **0.0 Seconds** | Synchronous replication to Frankfurt Zone B standby flushes WAL before write ACK. |
| **Recovery Time Objective (RTO)** | **< 15 Seconds** | Raft consensus `etcd` detects primary lease expiration and promotes standby. |

---

## 2. PACELC Theorem Formal Evaluation

The PACELC theorem expands on Brewer's CAP theorem:
> *If there is a Partition (P), how does the system choose between Availability (A) and Consistency (C); Else (E), when normal, how does it trade off Latency (L) and Consistency (C)?*

### Application to ApexPay Global:

```
PACELC classification:   PC / EC  (ledger writes)   versus   PA / EL  (balance views)
```

1. **Financial Ledger Writes (PC / EC):**
   - **Under Partition (PC):** The core banking ledger strictly selects **Consistency (C)** over Availability (A). If Frankfurt Zone A cannot communicate with Zone B, the primary refuses to accept uncommitted ledger writes. Preventing phantom money creation takes absolute precedence over system availability.
   - **Under Normal Operation (EC):** The system chooses **Consistency (C)** over Latency (L). Writes wait 4 ms for synchronous standby confirmation rather than returning immediately.

2. **Customer Balance Lookups (PA / EL):**
   - **Under Partition (PA):** Read replicas in Virginia and Tokyo continue serving balance queries from local cache.
   - **Under Normal Operation (EL):** Selects **Latency (L)** over strict linearizability, offloading 85% of read traffic from the Frankfurt primary.

> [!NOTE]
> The PC/EC classification for ledger writes is what makes RPO = 0 achievable. A system classified PA/EL on the write path would accept the write locally and reconcile afterwards, which permits a window in which a credited balance does not exist anywhere else.
