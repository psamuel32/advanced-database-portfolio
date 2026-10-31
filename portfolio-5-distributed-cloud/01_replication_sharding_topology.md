# Multi-Region Replication & Sharding Topology Specification

## 1. Physical Node Allocation

```
                               [ Client API Gateway / PgBouncer ]
                                       │              │
                    (Writes: Port 5432)│              │(Reads: Port 5433)
                                       ▼              ▼
           ┌──────────────────────────────────────┐  ┌────────────────────────────────────┐
           │ europe-west3-a (Frankfurt, Zone A)   │  │ europe-west3-b (Frankfurt, Zone B) │
           │ Role: PRIMARY (Read / Write)         │  │ Role: SYNCHRONOUS STANDBY          │
           │ Replication: Synchronous Stream      │◄─┼─► RPO = 0 Seconds (Zero Data Loss) │
           └──────────────────┬───────────────────┘  └────────────────────────────────────┘
                              │
                    Asynchronous WAL Stream
                    (Replication Lag: 64ms - 180ms)
                              │
               ┌──────────────┴──────────────┐
               ▼                             ▼
  ┌───────────────────────────┐ ┌───────────────────────────┐
  │ us-east1 (N. Virginia)    │ │ asia-northeast1 (Tokyo)   │
  │ Role: READ-REPLICA        │ │ Role: READ-REPLICA        │
  │ Workload: Balance queries │ │ Workload: Balance queries │
  └───────────────────────────┘ └───────────────────────────┘
```

---

## 2. Replication Parameter Settings (postgresql.conf)
```ini
# Synchronous Replication for Zero Data Loss
synchronous_commit = on
synchronous_standby_names = 'FIRST 1 (standby_zone_b)'
wal_level = replica
max_wal_senders = 10
wal_keep_size = 8192MB
max_standby_streaming_delay = 30s
hot_standby = on
```
