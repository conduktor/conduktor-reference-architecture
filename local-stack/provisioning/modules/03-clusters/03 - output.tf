
output "clusters" {
  value = { for cluster in conduktor_console_kafka_cluster_v2.clusters : cluster.name => cluster }
}
