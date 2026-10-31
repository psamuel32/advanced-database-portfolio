# Portfolio 5: Distributed and Cloud Database Architecture

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Citus](https://img.shields.io/badge/Citus-hash%20sharded-336791)
![Patroni](https://img.shields.io/badge/Patroni-etcd%20quorum-yellow)
![Availability](https://img.shields.io/badge/availability-99.999%25-success)

Author: Praise Samuel (p.okoro4197@miva.edu.ng)

---

## 1. Architecture Summary

This directory documents the distributed topology for ApexPay Global, designed for 99.999% availability, zero committed data loss, and horizontal scaling across 4.5 million daily transactions.

```diff
- Single-region primary with no standby and no horizontal distribution
+ Read/write primary in europe-west3-a (Frankfurt)
+ Synchronous in-region standby in europe-west3-b          -- RPO = 0
+ Asynchronous read replicas in us-east1 and asia-northeast1
+ Citus hash sharding on account_id with colocated ledger entries
+ Patroni leader election over an etcd consensus quorum
```

---

## 2. Objectives and Mechanisms

| Objective | Target | Mechanism |
| :--- | :--- | :--- |
| Durability | RPO = 0 seconds | Synchronous in-region standby confirming each commit |
| Availability | 99.999% with RTO under 15 seconds | Patroni leader election over an etcd quorum with split-brain fencing |
| Read scalability | Regional read offload | Asynchronous replicas in `us-east1` and `asia-northeast1` |
| Write scalability | Horizontal distribution | Citus hash sharding on `account_id`, with ledger entries colocated on the same shard |
| Data lifecycle | Partition pruning and tiering | Monthly range partitions on `transactions`, for example `transactions_2026_m10` |

> [!IMPORTANT]
> Ledger entries are sharded on the same key as their parent account. This colocates the two tables so that most join queries execute locally on a single worker node, avoiding the latency of a distributed two-phase commit.

---

## 3. Configuration Files

- `01_replication_sharding_topology.md`: Topology specification and replication lag calculations.
- `02_patroni_cluster_config.yaml`: Patroni distributed configuration store cluster with health probes and failover thresholds.
- `03_citus_sharding_setup.sql`: Distributed table definitions and temporal range partition scripts.
- `04_cap_pacelc_resilience_study.md`: Availability targets, RPO and RTO figures, and the PACELC trade-off study.

---

## 4. Trade-off Analysis

Under a network partition the ledger prioritises consistency over availability. If a quorum cannot be validated, writes are refused rather than accepted against a stale replica, because accepting a write that cannot be reconciled would permit the creation of money that does not exist.

Under normal operation the platform is both consistent and latency-sensitive in different places: writes require synchronous standby acknowledgement, while balance enquiries are routed to the nearest regional read replica. This is the EC/EL branch of the PACELC formulation, where the system trades latency for consistency on the write path and consistency for latency on the read path.

> [!WARNING]
> Synchronous replication adds a network round trip of roughly 4 ms to every payment commit. This cost is accepted deliberately, because it is the only mechanism considered here that guarantees zero committed data loss under a datacentre failure.
