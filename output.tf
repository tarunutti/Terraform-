output "aurora_cluster_endpoint" {
  value = aws_rds_cluster.aurora_postgresql.endpoint
}

output "aurora_reader_endpoint" {
  value = aws_rds_cluster.aurora_postgresql.reader_endpoint
}

output "aurora_proxy_endpoint" {
  value = aws_db_proxy.rds_proxy.endpoint
}
