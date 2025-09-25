#!/usr/bin/env bash

set -euo pipefail

# Function to display usage
usage() {
    echo "Usage: $0 <CLUSTER_ID> [S3_BUCKET] [--profile PROFILE_FILE]"
    echo ""
    echo "Arguments:"
    echo "  CLUSTER_ID    EMR cluster ID (required)"
    echo "  S3_BUCKET     S3 bucket name (optional, defaults to \$YOUR_S3_BUCKET environment variable)"
    echo "  --profile     Path to configuration profile file (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 j-1234567890ABCDEF my-benchmark-bucket"
    echo "  $0 j-1234567890ABCDEF --profile configs/high-memory.profile"
    echo "  $0 j-1234567890ABCDEF my-bucket --profile configs/quick-test.profile"
    exit 1
}

# Parse arguments
CLUSTER_ID=""
S3_BUCKET=""
PROFILE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            usage
            ;;
        *)
            if [ -z "$CLUSTER_ID" ]; then
                CLUSTER_ID="$1"
            elif [ -z "$S3_BUCKET" ]; then
                S3_BUCKET="$1"
            else
                echo "Error: Too many positional arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate input parameters
if [ -z "$CLUSTER_ID" ]; then
    echo "Error: Cluster ID is required as the first parameter"
    echo ""
    usage
fi

# Validate cluster ID format
if [[ ! $CLUSTER_ID =~ ^j-[A-Za-z0-9]+$ ]]; then
    echo "Error: Invalid cluster ID format. EMR cluster IDs should start with 'j-' followed by alphanumeric characters"
    echo "Provided: $CLUSTER_ID"
    echo ""
    usage
fi

# Set default S3 bucket
S3_BUCKET="${S3_BUCKET:-${YOUR_S3_BUCKET:-perflab-spark-data}}"

# Validate S3 bucket is specified
if [ -z "$S3_BUCKET" ]; then
    echo "Error: S3 bucket must be specified either as parameter or via YOUR_S3_BUCKET environment variable"
    echo ""
    usage
fi

PROFILE_NAME="TPCDS Benchmark Job"

# Default Spark Configuration Parameters
SPARK_DRIVER_CORES="4"
SPARK_DRIVER_MEMORY="5g"
SPARK_DRIVER_MEMORY_OVERHEAD="1000"
SPARK_EXECUTOR_CORES="4"
SPARK_EXECUTOR_MEMORY="6g"
SPARK_EXECUTOR_MEMORY_OVERHEAD="2G"
SPARK_EXECUTOR_INSTANCES="35"
SPARK_NETWORK_TIMEOUT="2000"
SPARK_EXECUTOR_HEARTBEAT_INTERVAL="300s"
SPARK_DYNAMIC_ALLOCATION_ENABLED="false"
SPARK_SHUFFLE_SERVICE_ENABLED="false"
SPARK_VERSION="3.5.5"

# Default Application Configuration
JAR_PATH_TEMPLATE="s3://${S3_BUCKET}/spark-tpcds/spark-benchmark-assembly-\${SPARK_VERSION}.jar"
INPUT_PATH="s3://${S3_BUCKET}/data/TPCDS-3TB-partitioned"
OUTPUT_PATH="s3://${S3_BUCKET}/logs/TEST-3TB-RESULT"
TPCDS_TOOLS_PATH="/opt/tpcds-kit/tools"
DATA_FORMAT="parquet"
SCALE_FACTOR="3000"
ITERATIONS="3"
OPTIMIZE_WRITES="false"
RESULT_COLLECTION="true"
TPCDS_QUERIES="q1-v2.4"

# Load profile if specified
if [ -n "$PROFILE_FILE" ]; then
    if [ ! -f "$PROFILE_FILE" ]; then
        echo "Error: Profile file '$PROFILE_FILE' not found"
        exit 1
    fi
    
    echo "Loading configuration profile: $PROFILE_FILE"
    
    # Source the profile file
    source "$PROFILE_FILE"
    echo "Configuration profile loaded successfully"
fi

# Resolve JAR_PATH template
JAR_PATH=$(eval echo "$JAR_PATH_TEMPLATE")

echo "=== Configuration Summary ==="
echo "EMR Cluster ID: $CLUSTER_ID"
echo "S3 Bucket: $S3_BUCKET"
echo "Profile File: ${PROFILE_FILE:-"None (using defaults)"}"
echo "Spark Version: $SPARK_VERSION"
echo "Driver Memory: $SPARK_DRIVER_MEMORY"
echo "Executor Memory: $SPARK_EXECUTOR_MEMORY"
echo "Executor Instances: $SPARK_EXECUTOR_INSTANCES"
echo "TPC-DS Queries: $TPCDS_QUERIES"
echo "Iterations: $ITERATIONS"
echo "Profile Name: $PROFILE_NAME"
echo "============================="
echo ""


ZING_EXTRA_CONF=""

runtime=$(cat terraform.tfvars | grep runtime_variant | awk '{print $3}' | awk -F['"'] '{print $2}')
if [ "$runtime" == "zing" ]; then
    echo "Using Zing runtime configuration"
    # Properly escape JVM options for JSON
    JVM_OPTIONS="-Xlog:gc*:file=/mnt/vmoutput/gc-${PROFILE_NAME}-pid%p.log::filecount=0 -XX:+PrintCompilation ${CURR_OPT_CONF} -XX:+TraceDeoptimization"
    # Escape for JSON - replace double quotes and handle special characters
    JVM_OPTIONS_ESCAPED=$(echo "$JVM_OPTIONS" | sed 's/"/\\"/g')
    echo "Zing extra options: $JVM_OPTIONS_ESCAPED"
else
    echo "Using default runtime configuration"
    JVM_OPTIONS_ESCAPED=""
fi


TPCDS_QUERIES_CLEAN="${TPCDS_QUERIES//\\,/,}"

# Build EMR step using proper JSON array format
if [ -n "$JVM_OPTIONS_ESCAPED" ]; then
    STEP_JSON=$(cat <<EOF
{
    "Type": "Spark",
    "Name": "${PROFILE_NAME}",
    "ActionOnFailure": "CONTINUE",
    "Args": [
        "--deploy-mode", "cluster",
        "--class", "com.amazonaws.eks.tpcds.BenchmarkSQL",
        "--conf", "spark.driver.cores=${SPARK_DRIVER_CORES}",
        "--conf", "spark.executor.extraJavaOptions=${JVM_OPTIONS_ESCAPED}",
        "--conf", "spark.driver.memory=${SPARK_DRIVER_MEMORY}",
        "--conf", "spark.executor.cores=${SPARK_EXECUTOR_CORES}",
        "--conf", "spark.executor.memory=${SPARK_EXECUTOR_MEMORY}",
        "--conf", "spark.executor.instances=${SPARK_EXECUTOR_INSTANCES}",
        "--conf", "spark.network.timeout=${SPARK_NETWORK_TIMEOUT}",
        "--conf", "spark.executor.heartbeatInterval=${SPARK_EXECUTOR_HEARTBEAT_INTERVAL}",
        "--conf", "spark.executor.memoryOverhead=${SPARK_EXECUTOR_MEMORY_OVERHEAD}",
        "--conf", "spark.driver.memoryOverhead=${SPARK_DRIVER_MEMORY_OVERHEAD}",
        "--conf", "spark.dynamicAllocation.enabled=${SPARK_DYNAMIC_ALLOCATION_ENABLED}",
        "--conf", "spark.shuffle.service.enabled=${SPARK_SHUFFLE_SERVICE_ENABLED}",
        "${JAR_PATH}",
        "${INPUT_PATH}",
        "${OUTPUT_PATH}",
        "${TPCDS_TOOLS_PATH}",
        "${DATA_FORMAT}",
        "${SCALE_FACTOR}",
        "${ITERATIONS}",
        "${OPTIMIZE_WRITES}",
        "${TPCDS_QUERIES_CLEAN}",
        "${RESULT_COLLECTION}"
    ]
}
EOF
)
else
    STEP_JSON=$(cat <<EOF
{
    "Type": "Spark",
    "Name": "${PROFILE_NAME}",
    "ActionOnFailure": "CONTINUE",
    "Args": [
        "--deploy-mode", "cluster",
        "--class", "com.amazonaws.eks.tpcds.BenchmarkSQL",
        "--conf", "spark.driver.cores=${SPARK_DRIVER_CORES}",
        "--conf", "spark.driver.memory=${SPARK_DRIVER_MEMORY}",
        "--conf", "spark.executor.cores=${SPARK_EXECUTOR_CORES}",
        "--conf", "spark.executor.memory=${SPARK_EXECUTOR_MEMORY}",
        "--conf", "spark.executor.instances=${SPARK_EXECUTOR_INSTANCES}",
        "--conf", "spark.network.timeout=${SPARK_NETWORK_TIMEOUT}",
        "--conf", "spark.executor.heartbeatInterval=${SPARK_EXECUTOR_HEARTBEAT_INTERVAL}",
        "--conf", "spark.executor.memoryOverhead=${SPARK_EXECUTOR_MEMORY_OVERHEAD}",
        "--conf", "spark.driver.memoryOverhead=${SPARK_DRIVER_MEMORY_OVERHEAD}",
        "--conf", "spark.dynamicAllocation.enabled=${SPARK_DYNAMIC_ALLOCATION_ENABLED}",
        "--conf", "spark.shuffle.service.enabled=${SPARK_SHUFFLE_SERVICE_ENABLED}",
        "${JAR_PATH}",
        "${INPUT_PATH}",
        "${OUTPUT_PATH}",
        "${TPCDS_TOOLS_PATH}",
        "${DATA_FORMAT}",
        "${SCALE_FACTOR}",
        "${ITERATIONS}",
        "${OPTIMIZE_WRITES}",
        "${TPCDS_QUERIES_CLEAN}",
        "${RESULT_COLLECTION}"
    ]
}
EOF
)
fi

# Submit the EMR step using the properly formatted JSON
echo "Submitting step with configuration:"
echo "$STEP_JSON"
echo "$STEP_JSON" | jq '.'

aws emr add-steps \
    --cluster-id "${CLUSTER_ID}" \
    --steps "$STEP_JSON"

echo "Step submitted successfully!"