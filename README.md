AWS Aurora PostgreSQL Production Cluster using Terraform!
This setup includes:

Aurora PostgreSQL with read replicas 🚀

RDS Proxy for optimized connection pooling

Secrets Manager for secure DB credentials

TLS enforcement for secure client connections

KMS encryption for data at rest

Highly available, distributed across multiple AZs

Custom parameter group to enable pgvector extension for AI applications

Major AWS Services used:

RDS Aurora PostgreSQL

RDS Proxy

Secrets Manager

KMS

Terraform Remote State (with S3 backend)

IAM Role for Proxy Access

🛡️ Security:

Enforced TLS on proxy connections

Secrets encrypted with KMS

VPC Security Groups allowing only whitelisted CIDRs
