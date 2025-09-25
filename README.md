# EMR TPC-DS Benchmarking Toolkit

An automated toolkit for running Apache Spark TPC-DS performance benchmarks on Amazon EMR with different JVM runtimes. This project allows you to compare performance between Azul Zing, Azul Zulu, and Amazon Corretto JVMs using standardized TPC-DS workloads.

## Features

- **Infrastructure as Code**: Complete Terraform automation for EMR cluster provisioning
- **Multi-JVM Support**: Compare Azul Zing, Azul Zulu, and Amazon Corretto performance
- **Flexible Networking**: Works with existing VPCs or creates new infrastructure
- **Configurable Profiles**: Pre-defined configurations for different test scenarios
- **Monitoring Tools**: Built-in scripts for job status and cluster monitoring
- **Automated Bootstrap**: Custom JDK installation and performance tuning

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.0+)
   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
   sudo installer -pkg AWSCLIV2.pkg -target /

   # Configure with your credentials
   aws configure
   ```

2. **Terraform CLI** (v1.12.0+)
   ```bash
   # macOS
   brew install terraform

   # Linux
   wget https://releases.hashicorp.com/terraform/1.12.0/terraform_1.12.0_linux_amd64.zip
   unzip terraform_1.12.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **jq** (for JSON processing in monitoring scripts)
   ```bash
   # macOS
   brew install jq

   # Linux
   sudo apt-get install jq  # Ubuntu/Debian
   sudo yum install jq      # CentOS/RHEL
   ```

### AWS Prerequisites

1. **AWS Account**: With appropriate permissions for EMR, EC2, VPC, and S3
2. **EC2 Key Pair**: For SSH access to cluster nodes
3. **S3 Bucket**: For storing benchmark data, logs, and bootstrap scripts
4. **IAM Permissions**: Ensure your AWS credentials have permissions for:
   - EMR cluster creation and management
   - EC2 instance management
   - VPC and networking (if creating new VPC)
   - S3 bucket access
   - IAM role creation for EMR service roles

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd emr-tpcds
```

### 2. Prepare S3 Bucket and Data

Create an S3 bucket for your benchmarks (replace `your-benchmark-bucket` with your actual bucket name):

```bash
# Create S3 bucket
aws s3 mb s3://your-benchmark-bucket --region us-west-2

# Set environment variable for convenience
export YOUR_S3_BUCKET=your-benchmark-bucket
```

**Important**: This repository does not include TPC-DS data generation. You need to:
- Generate TPC-DS data using official TPC-DS tools or Spark's data generation utilities
- Upload the data to `s3://your-bucket/data/sf15000-parquet/` (for 15TB dataset)
- Ensure data is partitioned appropriately for optimal Spark performance

We did 15TB dataset with this tool: [single-node data generator](https://github.com/imorph/tpctools)
But it is possible to do it in more Spark-native way with [this](https://github.com/BlueGranite/tpc-ds-dataset-generator)
Benchmark JAR was built from instructions [here](https://github.com/aws-samples/emr-spark-benchmark/blob/main/build-instructions.md)

### 3. Prepare JDK Download URLs

If using custom JDKs (Azul Zing or Zulu), you need to prepare download URLs:

#### For Azul Zulu (Open Source)
1. Visit [Azul Downloads](https://www.azul.com/downloads/#downloads-table-zulu)
2. Select: Java 17, Linux, ARM 64-bit, .tar.gz format
3. Copy the download URL

#### For Azul Zing (Commercial)
1. Contact Azul Systems for access to Zing JDK
2. Obtain download URL for Linux ARM64 .tar.gz format

#### Update Terraform Variables
Edit the JDK URLs in `variables.tf`:

```hcl
locals {
  default_tar_urls = {
    zulu    = "https://cdn.azul.com/zulu/bin/zulu17.50.19-ca-jdk17.0.11-linux_aarch64.tar.gz"
    zing    = "https://your-repository.com/path/to/zing-jdk17-linux_aarch64.tar.gz"
    default = ""
  }
}
```

### 4. Configure Terraform Variables

Create or edit `terraform.tfvars`:

```hcl
# Required variables
log_bucket           = "your-benchmark-bucket"
scripts_bucket       = "your-benchmark-bucket"
ssh_key_name        = "your-ec2-key-name"

# JVM runtime selection
runtime_variant     = "zing"  # Options: "zing", "zulu", "default"

# Instance configuration
master_instance_type = "c8gd.2xlarge"
core_instance_type   = "c8gd.8xlarge"
core_instance_count  = 3

# Optional: Use existing VPC (both required if using existing)
# existing_vpc_id     = "vpc-1234567890abcdef0"
# existing_subnet_id  = "subnet-1234567890abcdef0"

# Optional: Custom regions and networking
# aws_region     = "us-west-2"
# vpc_cidr       = "10.20.0.0/16"
# subnet_cidr    = "10.20.0.0/24"
```

### 5. Deploy EMR Cluster

```bash
# Initialize Terraform
terraform init

# Plan deployment (optional)
terraform plan

# Deploy cluster
terraform apply

# Save cluster ID
export CURRENT_SPARK_CLUSTER_ID=$(terraform output -raw cluster_id)
echo "Cluster ID: $CURRENT_SPARK_CLUSTER_ID"
```

### 6. Run Benchmark

```bash
# Run with default configuration
./run_test.sh $CURRENT_SPARK_CLUSTER_ID your-benchmark-bucket

# Run with custom profile
./run_test.sh $CURRENT_SPARK_CLUSTER_ID your-benchmark-bucket --profile configs/15tb-full-run-zing.profile

# Run with environment variable for bucket (set YOUR_S3_BUCKET)
./run_test.sh $CURRENT_SPARK_CLUSTER_ID --profile configs/15tb-full-run-zing.profile
```

### 7. Monitor Progress

```bash
# Check job status
./status.sh

# Monitor cluster resources
./hosts.sh $CURRENT_SPARK_CLUSTER_ID

# Or with environment variable
CURRENT_SPARK_CLUSTER_ID=$CURRENT_SPARK_CLUSTER_ID ./hosts.sh
```

### 8. Cleanup

```bash
# Destroy cluster when done
terraform destroy
```

## Detailed Configuration

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `log_bucket` | S3 bucket for EMR logs | `"your-s3-bucket-name"` | Yes |
| `scripts_bucket` | S3 bucket for bootstrap scripts | `"your-s3-bucket-name"` | Yes |
| `ssh_key_name` | EC2 key pair name | `"your-ssh-key-name"` | Yes |
| `runtime_variant` | JVM runtime ("zing", "zulu", "default") | `"default"` | No |
| `existing_vpc_id` | Use existing VPC | `null` | No |
| `existing_subnet_id` | Use existing subnet | `null` | No |
| `master_instance_type` | Master node instance type | `"c7gd.2xlarge"` | No |
| `core_instance_type` | Core node instance type | `"c7gd.2xlarge"` | No |
| `core_instance_count` | Number of core instances | `1` | No |
| `aws_region` | AWS region | `"us-west-2"` | No |

### Using Existing VPC

If you have an existing VPC and subnet, specify both:

```hcl
existing_vpc_id    = "vpc-1234567890abcdef0"
existing_subnet_id = "subnet-1234567890abcdef0"
```

**Important**:
- Both variables must be provided together
- The subnet must have internet access (associated with route table that has internet gateway route)
- Subnet must have sufficient IP addresses for your cluster size
- VPC must have DNS hostnames and DNS resolution enabled

### Configuration Profiles

Profiles are bash scripts in the `configs/` directory that override default benchmark settings:

#### Key Profile Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SPARK_EXECUTOR_INSTANCES` | Number of Spark executors | `"11"` |
| `SPARK_EXECUTOR_MEMORY` | Memory per executor | `"10g"` |
| `SPARK_EXECUTOR_CORES` | CPU cores per executor | `"8"` |
| `INPUT_PATH` | S3 path to TPC-DS data | `"s3://bucket/data/sf15000-parquet"` |
| `OUTPUT_PATH` | S3 path for results | `"s3://bucket/logs/TEST-15TB-RESULT"` |
| `ITERATIONS` | Number of benchmark iterations | `"3"` |
| `TPCDS_QUERIES` | Comma-separated query list | `"q1-v2.4,q2-v2.4,..."` |
| `CURR_OPT_CONF` | JVM-specific options | `"-XX:ActiveProcessorCount=8"` |

#### Creating Custom Profiles

```bash
# Copy existing profile
cp configs/15tb-full-run-default.profile configs/my-custom.profile

# Edit configuration
vi configs/my-custom.profile

# Use custom profile
./run_test.sh $CLUSTER_ID $BUCKET --profile configs/my-custom.profile
```

## Monitoring and Debugging

### Monitoring Scripts

1. **Status Monitoring** (`status.sh`):
   - Shows EMR step status and timing
   - Requires `CURRENT_SPARK_CLUSTER_ID` environment variable

2. **Host Monitoring** (`hosts.sh`):
   - Shows CPU, memory, and disk usage per node
   - Supports parallel SSH connections for faster execution

#### Host Monitoring Configuration

```bash
# Configure SSH settings
export SSH_USER=ec2-user
export SSH_KEY=~/.ssh/your-key.pem
export PARALLEL=1          # Enable concurrent SSH
export JOBS=8              # Max concurrent connections

# Run monitoring
./hosts.sh $CLUSTER_ID
```

### Log Locations

- **EMR Service Logs**: `s3://your-bucket/logs/emr/cluster-id/`
- **Application Logs**: `s3://your-bucket/logs/emr/cluster-id/containers/`
- **Bootstrap Logs**: `/tmp/bootstrap.log` on cluster nodes
- **Benchmark Results**: `s3://your-bucket/logs/TEST-*-RESULT/`

### Common Issues and Troubleshooting

1. **Cluster Creation Fails**:
   - Check AWS service limits (EC2 instances, VPC limits)
   - Verify IAM permissions
   - Ensure availability zone has requested instance types

2. **Bootstrap Failures**:
   - Check JDK download URL accessibility
   - Verify S3 bucket permissions for bootstrap script
   - Review `/tmp/bootstrap.log` on cluster nodes

3. **Job Execution Failures**:
   - Verify TPC-DS data exists in specified S3 path
   - Check Spark configuration parameters match cluster capacity
   - Review EMR step logs in AWS Console

4. **SSH Access Issues**:
   - Ensure security group allows SSH (port 22) from your IP
   - Verify EC2 key pair is correct
   - Check VPC/subnet internet gateway configuration

## Cost Considerations

### Instance Costs
- **c8gd.2xlarge**: ~$0.77/hour
- **c8gd.8xlarge**: ~$3.07/hour
- **c7gd.2xlarge**: ~$0.69/hour

### Example Cluster Cost (3 c8gd.8xlarge + 1 c8gd.2xlarge master):
- **Hourly**: ~$10/hour
- **Full benchmark** (3-4 hours): ~$30-40

## Performance Tuning

### JVM-Specific Optimizations

1. **Azul Zing**:
   - Uses concurrent garbage collection
   - Custom JVM options in `CURR_OPT_CONF`
   - Automatic heap management

2. **Azul Zulu**:
   - OpenJDK-based with performance improvements
   - Standard HotSpot optimizations

3. **Amazon Corretto (default)**:
   - AWS-optimized OpenJDK
   - Pre-configured for EMR environment

### Spark Configuration Tuning

Key parameters to adjust based on your cluster:

```bash
# Memory configuration
SPARK_EXECUTOR_MEMORY="10g"           # Per executor memory
SPARK_EXECUTOR_MEMORY_OVERHEAD="3g"   # Additional memory for overhead

# CPU configuration
SPARK_EXECUTOR_CORES="8"              # Cores per executor
SPARK_EXECUTOR_INSTANCES="11"         # Total executors

# Network and reliability
SPARK_NETWORK_TIMEOUT="300s"          # Network timeout
SPARK_EXECUTOR_HEARTBEAT_INTERVAL="10s"  # Heartbeat frequency
```
