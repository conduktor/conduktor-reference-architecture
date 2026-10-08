## Platform sizing

Each component has a different load driver: Gateway scales with the traffic it proxies, Console with the size of the Kafka estate it manages and the number of users, PostgreSQL with both. Size each one on its own driver, start from the figures below, then adjust from the metrics you collect in production.

Figures come from the Conduktor [system requirements](https://docs.conduktor.io/guide/conduktor-in-production/system-requirements), [PostgreSQL sizing](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-console/postgres-sizing) and the [Helm charts](https://github.com/conduktor/conduktor-public-charts).

### Gateway

Gateway is mostly CPU-bound. Its load comes from sustained throughput and from the interceptors applied to that traffic. Interceptors doing heavy inspection, such as encryption, need more CPU and more memory (4 GB of RAM per CPU). The caching interceptor adds memory and disk.

| Per instance | CPU | Memory | Sustained throughput |
|--------------|-----|--------|----------------------|
| Minimum      | 2   | 4 GB   | ~20–30 MB/s          |
| Recommended  | 4   | 8 GB   | ~40–50 MB/s          |

Instance count: enough instances to carry peak throughput with one instance down, and never fewer than 3. For example, 120 MB/s at peak on recommended instances needs 3 instances for the load plus 1 for headroom: 4 instances.

The throughput figures assume light interceptors. Measure with your own message sizes and interceptor chain before committing to a count.

### Console

| Per instance | CPU | Memory | Disk  |
|--------------|-----|--------|-------|
| Minimum      | 2   | 3 GB   | 5 GB  |
| Recommended  | 4+  | 4+ GB  | 10+ GB |

Run at least 2 instances. Console is stateless, so adding instances adds capacity for users and API calls. Each instance opens up to 15 connections to PostgreSQL by default (`CDK_DATABASE_CONNECTION_POOL_SIZE`).

### Console Cortex

Cortex runs as a single instance. The chart defaults (requests 0.5 CPU / 500 Mi, limits 2 CPU / 2 Gi) suit most deployments; raise them if scrape volume grows.

Its persistent volume only holds the working set before metrics are offloaded to object storage: 20 Gi is enough for small to medium deployments, and large deployments with high scrape volume can need 200 Gi or more. Grow the volume if compaction falls behind.

### PostgreSQL

Pick the level from your highest dimension: 150 users with 100,000 topics is a mid-scale or fully scaled deployment, not a standard one.

| Level        | Concurrent users | Kafka scale                                                         | Max DB size |
|--------------|------------------|---------------------------------------------------------------------|-------------|
| Standard     | up to 500        | 1–5 clusters, up to 1,000 topics / 10,000 partitions, ~500 consumer groups | up to 50 GB  |
| Mid scale    | 500–1,000        | 5–10 clusters, up to 5,000 topics / 50,000 partitions, ~1,000 consumer groups | up to 100 GB |
| Fully scaled | 1,000–5,000      | 10+ clusters, 5,000+ topics / 50,000+ partitions, 1,000+ consumer groups | up to 250 GB |

Reference instances on AWS RDS (the docs give equivalents for GCP and Azure):

| Level        | Instance                          | Storage  | IOPS          |
|--------------|-----------------------------------|----------|---------------|
| Standard     | `db.m6g.large` (2 vCPU, 8 GB)     | 50 GB+   | 3,000         |
| Mid scale    | `db.m6g.xlarge` (4 vCPU, 16 GB)   | 150 GB+  | 5,000–8,000   |
| Fully scaled | `db.m6g.2xlarge` (8 vCPU, 32 GB)  | 500 GB+  | 15,000–30,000 |

- Provision at least 3,000 IOPS: Console syncs Kafka metadata to the database continuously and the sync is write-heavy.
- Set `max_connections` to at least `Console instances × 15 + 10`, e.g. 55 for 3 instances.
- 1–2 vCPU, 1 GB of RAM and 10 GB of disk are only suitable for proof-of-concept environments.
- On AWS RDS or Aurora, use PostgreSQL 14.8+ or 15.3+.
- Enable automated backups, with 14 to 30 days of retention in production.
