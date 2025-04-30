## Platform Sizing (estimated)

### Console
The following table provides a rough estimate of the resources required for the Conduktor Console based on the expected load. 
The load is defined by the number of Kafka clusters, brokers, topics, partitions, consumers, producers, users, and groups the Console will manage.

| Size   | Max Kafka cluster | Total Kafka brokers | Total Kafka Topics | Total Kafka Partitions | Consumers | Producer | Conduktor users | Conduktor groups |
|--------|-------------------|---------------------|--------------------|------------------------|-----------|----------|-----------------|------------------|
| Small  | 2                 | 6                   | 1000               | 10000                  | 50        | 50       | 100             | 20               |
| Medium | 5                 | 25                  | 10000              | 100000                 | 1000      | 1000     | 300             | 100              |
| Large  | 15                | 50                  | 50000              | 1000000                | 10000     | 50000    | 1000            | 1000             |


#### Console Resource Requirements
The following table provides the estimated CPU and memory requirements for the Console based on the expected load:

| Size   | CPU    | Memory |
|--------|--------|--------|
| Small  | 2 vCPU | 4 Gi   |
| Medium | 3 vCPU | 6 Gi   |
| Large  | 4 vCPU | 8 Gi   |

#### Cortex Resource Requirements
The following table provides the estimated CPU and memory requirements for the Console Cortex based on the expected load:

| Size   | CPU      | Memory |
|--------|----------|--------|
| Small  | 2 vCPU   | 2 Gi   |
| Medium | 2 vCPU   | 4 Gi   |
| Large  | 4 vCPU   | 8 Gi   |

#### Main PostgreSQL Resource Requirements
The following table provides the estimated CPU and memory and storage requirements for the Console main Postgresql database on the expected load:

| Size   | CPU     | Memory  | Disk    |
|--------|---------|---------|---------|
| Small  | 2 vCPU  | 4 Gi    | 10 Gi   |
| Medium | 2 vCPU  | 4 Gi    | 20 Gi   |
| Large  | 4 vCPU  | 6 Gi    | 40 Gi   |

#### SQL PostgreSQL Resource Requirements
The following table provides the estimated CPU and memory and storage requirements for the Console SQL Postgresql database on the expected load:

| Size   | CPU    | Memory | Disk (*) |
|--------|--------|--------|----------|
| Small  | 2 vCPU | 4 Gi   | 10 Gi    |
| Medium | 2 vCPU | 4 Gi   | 50 Gi    |
| Large  | 4 vCPU | 6 Gi   | 100 Gi   |

*: Disk size is linked to SQL usage, indexed topic size, and index retention.

### Gateway Resource Requirements
The following table provides the estimated CPU and memory requirements for the Gateway based on the expected load:

| Size   | CPU    | Memory |
|--------|--------|--------|
| Small  | 2 vCPU | 4 Gi   |
| Medium | 4 vCPU | 8 Gi   |
| Large  | 4 vCPU | 8 Gi   |

### Additional Notes
- **Small**: Suitable for development or small-scale environments with minimal Kafka resources and low traffic.
- **Medium**: Designed for mid-sized production environments with moderate Kafka resources and traffic.
- **Large**: Intended for large-scale production environments with high Kafka resource usage and significant traffic throughput.

In addition to vertical scaling, you can also horizontally scale the Conduktor Console and Gateway by deploying multiple instances of each component. This is particularly useful for high availability and load balancing in production environments.