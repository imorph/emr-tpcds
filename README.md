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

4. **uv** (for Python dependency management and script execution)
   ```bash
   # macOS and Linux
   curl -LsSf https://astral.sh/uv/install.sh | sh

   # Or with pip
   pip install uv

   # Or with Homebrew (macOS)
   brew install uv
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

#### Azul Zing

**Key Features:**
- Concurrent garbage collection (C4) with sub-millisecond pause times
- ReadyNow warm-up elimination technology
- Automatic heap management

**Essential JVM flags for TPC-DS:**

```bash
-XX:ActiveProcessorCount=$SPARK_EXECUTOR_CORES
-XX:TopTierCompileThresholdTriggerMillis=60000
-XX:ProfileLogIn=/mnt/vmoutput/tpcds-15tb-full-gen1.profile
```

**ReadyNow Profile Training:**

For production benchmarks, you must train ReadyNow profiles to eliminate JVM warm-up variance. Pre-configured profiles are available:
- `configs/15tb-zing-gen0.profile` - Initial profile collection
- `configs/15tb-zing-gen1.profile` - Refined profile training
- `configs/15tb-zing-production.profile` - Production measurements

**→ See [Training Zing ReadyNow Profiles for TPC-DS](#training-zing-readynow-profiles-for-tpc-ds) section below for complete step-by-step training instructions.**

#### Azul Zulu
 - OpenJDK-based with performance improvements
 - Standard HotSpot optimizations

#### Amazon Corretto (default)
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

Following config included by default for all JVMs in `main.tf`:

```yaml
# With IDs in names -> new classes per batch -> less profile reuse, extra code-cache churn. Without IDs -> same generated class reused -> profiles and compiled methods persist lower steady-state latency
spark.sql.codegen.useIdInClassName: false

# The global cache of generated classes defaults to 100 entries once you exceed that, Spark evicts and recompiles classes, wasting CPU and lengthening query latency
spark.sql.codegen.cache.maxEntries: 9999
```

## Training Zing ReadyNow Profiles for TPC-DS

### Understanding ReadyNow Generations

ReadyNow profiles improve through iterative training. Each "generation" builds on the previous one:

1. **Generation 0 (Gen0)**: Initial cold-start profile collection
2. **Generation 1 (Gen1)**: Refined profile using Gen0 as input
3. **Production**: Final measurements using Gen1 for optimal performance

**Minimum Training Requirements:**
- Each generation requires running the full TPC-DS query suite (all 99+ queries)
- Multiple iterations (3+ recommended) ensure comprehensive method coverage

### Challenge: Distributed Spark Executors

In EMR Spark clusters, each executor JVM generates its own ReadyNow profile. With 11 executors, you'll get 11 profile files per run. For the next generation, you need to:
1. Collect profiles from all executors
2. Select one representative profile (typically the largest)
3. Distribute that profile to all executors for the next run

### Step-by-Step Training Process

#### Prerequisites

- EMR cluster deployed with `runtime_variant = "zing"`
- TPC-DS data available in S3 (`s3://your-bucket/data/sf15000-parquet/`)
- SSH access to cluster nodes configured
- Cluster ID saved: `export CURRENT_SPARK_CLUSTER_ID=j-XXXXXXXXXXXXX`

---

#### Generation 0: Initial Profile Collection

**1. Run benchmark with Gen0 configuration:**

```bash
# Deploy Zing cluster
terraform apply

# Run Gen0 training
./run_test.sh $CURRENT_SPARK_CLUSTER_ID your-bucket --profile configs/15tb-zing-gen0.profile
```

**2. Wait for completion (3-4 hours):**

```bash
# Monitor progress
./status.sh
```

**3. Collect Gen0 profiles from cluster nodes:**

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@$ONE_OF_THE_EXECUTORS_IP

# collect all Gen0 profiles
cd /mnt/vmoutput
ls -lh tpcds-15tb-full-gen0-*.profile

# Expected output: Multiple files, one per executor
# tpcds-15tb-full-gen0-12345.profile (3.2M)
# tpcds-15tb-full-gen0-12346.profile (3.1M)
# tpcds-15tb-full-gen0-12347.profile (3.3M)
# ...

# Select the largest profile (typically has best coverage)
# Rename for Gen1 input (remove process ID)
cp tpcds-15tb-full-gen0-12347.profile tpcds-15tb-full-gen0.profile
```

**4. Upload Gen0 profile to S3 (also you can use any HTTP seever to hold it for you, or even manually upload to EVERY executor host before each new run):**

```bash
aws s3 cp tpcds-15tb-full-gen0.profile s3://your-bucket/readynow-profiles/

exit
```

**5. Verify profile size:**

```bash
# Download and check locally
aws s3 cp s3://your-bucket/readynow-profiles/tpcds-15tb-full-gen0.profile .
ls -lh tpcds-15tb-full-gen0.profile
```

---

#### Generation 1: Refined Profile Collection

**1. Update bootstrap script to download Gen0 profile:**

Edit `bootstrap.sh.tpl` and uncomment/add the download section:

```bash
sudo mkdir -p /mnt/vmoutput
# Download Gen0 profile for Gen1 training
sudo curl -L -f --connect-timeout 30 --max-time 300 \
  -o /mnt/vmoutput/tpcds-15tb-full-gen0.profile \
  https://s3.amazonaws.com/your-bucket/readynow-profiles/tpcds-15tb-full-gen0.profile
sudo chmod -R 1777 /mnt/vmoutput
```

**2. Redeploy cluster with updated bootstrap:**

```bash
# Destroy old cluster
terraform destroy

# Deploy new cluster (will download Gen0 profile during bootstrap)
terraform apply
```

**3. Run Gen1 training:**

```bash
./run_test.sh $CURRENT_SPARK_CLUSTER_ID your-bucket --profile configs/15tb-zing-gen1.profile
```

**4. Collect and upload Gen1 profile (same process as Gen0):**

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@$ONE_OF_THE_EXECUTORS_IP

# Select best Gen1 profile
cd /mnt/vmoutput
cp tpcds-15tb-full-gen1-12347.profile tpcds-15tb-full-gen1.profile

# Upload to S3
aws s3 cp tpcds-15tb-full-gen1.profile s3://your-bucket/readynow-profiles/
exit
```

---

#### Production: Performance Measurement

**1. Update bootstrap script for Gen1 profile:**

Edit `bootstrap.sh.tpl` to download Gen1 instead of Gen0:

```bash
sudo mkdir -p /mnt/vmoutput
# Download Gen1 profile for production runs
sudo curl -L -f --connect-timeout 30 --max-time 300 \
  -o /mnt/vmoutput/tpcds-15tb-full-gen1.profile \
  https://s3.amazonaws.com/your-bucket/readynow-profiles/tpcds-15tb-full-gen1.profile
sudo chmod -R 1777 /mnt/vmoutput
```

**2. Deploy production cluster:**

```bash
terraform destroy
terraform apply
```

**3. Run production benchmarks:**

```bash
./run_test.sh $CURRENT_SPARK_CLUSTER_ID your-bucket --profile configs/15tb-zing-production.profile
```

This configuration uses Gen1 profile for optimal warm-start, producing consistent, production-ready benchmark results.


#### Check Bootstrap Logs if any problems with download profile

Verify profiles are loaded successfully:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@$ONE_OF_THE_EXECUTORS_IP

# Check bootstrap log
grep -i "readynow\|profile" /tmp/bootstrap.log

# Check profile exists and is readable
ls -lh /mnt/vmoutput/*.profile
file /mnt/vmoutput/*.profile  # Should show: data
```

---

### Profile Management Best Practices

#### Naming Convention

Use consistent naming for tracking generations:

```
s3://your-bucket/readynow-profiles/
├── tpcds-15tb-full-gen0.profile          # First generation
├── tpcds-15tb-full-gen1.profile          # Second generation
├── tpcds-15tb-full-gen0-20250130.profile # Archived with date
└── tpcds-15tb-full-gen1-20250130.profile # Archived with date
```

#### Version Control for Workload Changes

Regenerate profiles when:
- TPC-DS query list changes
- Spark configuration changes significantly (executor memory, cores)
- Upgrading Spark versions
- Upgrading Zing JDK versions

#### Multi-Cluster Reuse

A single trained profile can be reused across multiple clusters if:
- Same Spark version and configuration
- Same TPC-DS query workload
- Same Zing JDK version
- Similar cluster size (executor count can vary slightly)

### Troubleshooting ReadyNow Training

#### Problem: Profile Files Not Generated

**Symptoms:** No `.profile` files in `/mnt/vmoutput/` after benchmark run

**Solutions:**
1. Check JVM flags are passed correctly:
   ```bash
   # On cluster node during run
   ps aux | grep java | grep ProfileLogOut
   ```

2. Verify directory permissions:
   ```bash
   ls -ld /mnt/vmoutput/
   # Should show: drwxrwxrwt (1777 permissions)
   ```

3. Check for disk space:
   ```bash
   df -h /mnt/
   ```

#### Problem: Profile Download Fails in Bootstrap

**Symptoms:** Bootstrap errors or missing profile during run

**Solutions:**
1. Verify S3 URL is accessible:
   ```bash
   # Test from master node
   curl -I https://s3.amazonaws.com/your-bucket/readynow-profiles/tpcds-15tb-full-gen0.profile
   ```

2. Check IAM permissions for EMR EC2 role:
   - Must have `s3:GetObject` permission for profile bucket

3. Check bootstrap logs:
   ```bash
   tail -100 /tmp/bootstrap.log
   ```
---

### Additional Resources

- [Azul ReadyNow Documentation](https://docs.azul.com/prime/Use-ReadyNow-Training)
- [Optimizer Hub ReadyNow Orchestrator](https://docs.azul.com/optimizer-hub/) - Automated profile management (commercial tool)
- See `configs/15tb-full-run-zing.profile` for alternative inline configuration approach

## Evaluating Results

For evaluating results, we will use the data from Spark Event Logs. If `spark.eventLog.dir` is not set, to get AWS EMR Spark Event Logs:

1. In AWS EMR Web UI go to the cluster where the benchmark ran.
2. Start the Spark History UI by clicking on `Spark History Server`.
3. Wait for the Spark History UI to open, and wait until the Spark Event Logs from the benchmark runs are available (check by refreshing the page), and download them as `.zip` files.

### Analysis Tools

This repository includes two Python analysis scripts:

- **`spark_eventlog_analyze.py`**: Converts Spark event logs to aggregated CSV format with per-query metrics
- **`tpcds_eventlog_compare.py`**: Compares two configurations and generates comparison CSV and S-curve plots

#### Dependencies

The analysis scripts require Python 3.13+ with the following packages:
- `polars` - for efficient data processing
- `matplotlib` - for visualization

**Using uv (recommended)**:

All Python scripts in this repository can be run using `uv`, which automatically manages dependencies without needing a virtual environment:

```bash
# Run directly with uv - dependencies are automatically handled
uv run spark_eventlog_analyze.py -o zing-1.csv /path/to/eventLogs-application_1758748016442_0001-1.zip
uv run tpcds_eventlog_compare.py -o results corretto-*.csv zing-*.csv
```

**Alternative: Traditional Python environment**:

```bash
# Create virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install polars matplotlib

# Run scripts
python spark_eventlog_analyze.py -o zing-1.csv /path/to/eventlog.zip
python tpcds_eventlog_compare.py -o results corretto-*.csv zing-*.csv
```

### Step 1: Convert Event Logs to CSV

For each event log (JSON, optionally in `.zip` or `.gz`), convert it to a more lightweight aggregated CSV:

```bash
uv run spark_eventlog_analyze.py -o zing-1.csv /path/to/eventLogs-application_1758748016442_0001-1.zip
uv run spark_eventlog_analyze.py -o zing-2.csv /path/to/eventLogs-application_1758748016442_0002-1.zip
# ... repeat for additional runs

uv run spark_eventlog_analyze.py -o corretto-1.csv /path/to/eventLogs-application_1756681602934_0001-1.zip
uv run spark_eventlog_analyze.py -o corretto-2.csv /path/to/eventLogs-application_1756681602934_0002-1.zip
# ... repeat for additional runs
```

**Output CSV columns**: `executionId`, `description`, `num_jobs`, `num_tasks`, `makespan_ms`, `task_slot_ms`, `executor_run_ms`, `executor_cpu_ms`, `cpu_vs_wall_pct`, `deserialize_ms`, `result_serialize_ms`, `gc_ms`, `shuffle_fetch_wait_ms`, `shuffle_write_time_ms`, `input_bytes`, `output_bytes`, `shuffle_read_bytes`, `shuffle_write_bytes`

### Step 2: Compare Configurations

Compare the converted event logs of two configurations:

```bash
uv run tpcds_eventlog_compare.py -o results corretto-*.csv zing-*.csv
```

**Important**:
- Configuration names (e.g. `corretto`, `zing`) and run sequence numbers are implicitly derived from CSV file names in the format `{config}-{run}.csv`
- The first named configuration is taken as baseline
- Multiple runs of the same configuration are automatically aggregated by taking the mean

**Optional filters**:
```bash
# Only consider queries where target runs longer than 60 seconds
uv run tpcds_eventlog_compare.py -o results --longer-than 60 corretto-*.csv zing-*.csv
```

### Output

The result folder will contain:

```
results/
├── zing-vs-corretto.csv
└── zing-vs-corretto-total_time.png
```

- **PNG file**: S-curve comparison of the `total_time` metric (wall clock time to complete each query), sorted by speedup ratio
- **CSV schema**: `query`, `total_time_corretto`, `total_time_zing`, `executor_time_corretto`, `executor_time_zing`, `executor_cpu_time_corretto`, `executor_cpu_time_zing`

The CSV contains aggregated per-query metrics for both configurations and can be used for further analysis or custom plotting.
