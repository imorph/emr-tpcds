#!/bin/bash

PROFILE_NAME="zing-3i-8t-11e-8c-full-15tb"

SPARK_DRIVER_CORES="4"
SPARK_DRIVER_MEMORY="6g"
SPARK_DRIVER_MEMORY_OVERHEAD="2g"
SPARK_EXECUTOR_CORES="8"
SPARK_EXECUTOR_MEMORY="10g"
SPARK_EXECUTOR_MEMORY_OVERHEAD="3g"
SPARK_EXECUTOR_INSTANCES="11"
SPARK_NETWORK_TIMEOUT="300s"
SPARK_EXECUTOR_HEARTBEAT_INTERVAL="10s"
SPARK_DYNAMIC_ALLOCATION_ENABLED="false"
SPARK_SHUFFLE_SERVICE_ENABLED="true"
SPARK_VERSION="3.5.5"
INPUT_PATH="s3://${S3_BUCKET}/data/sf15000-parquet"
OUTPUT_PATH="s3://${S3_BUCKET}/logs/TEST-15TB-RESULT"


CURR_OPT_CONF="-XX:TopTierCompileThresholdTriggerMillis=60000 -XX:ActiveProcessorCount=8"

ITERATIONS="3"

TPCDS_QUERIES="q1-v2.4\,q10-v2.4\,q11-v2.4\,q12-v2.4\,q13-v2.4\,q14a-v2.4\,q14b-v2.4\,q15-v2.4\,q16-v2.4\,q17-v2.4\,q18-v2.4\,q19-v2.4\,q2-v2.4\,q20-v2.4\,q21-v2.4\,q22-v2.4\,q23a-v2.4\,q23b-v2.4\,q24a-v2.4\,q24b-v2.4\,q25-v2.4\,q26-v2.4\,q27-v2.4\,q28-v2.4\,q29-v2.4\,q3-v2.4\,q30-v2.4\,q31-v2.4\,q32-v2.4\,q33-v2.4\,q34-v2.4\,q35-v2.4\,q36-v2.4\,q37-v2.4\,q38-v2.4\,q39a-v2.4\,q39b-v2.4\,q4-v2.4\,q40-v2.4\,q41-v2.4\,q42-v2.4\,q43-v2.4\,q44-v2.4\,q45-v2.4\,q46-v2.4\,q47-v2.4\,q48-v2.4\,q49-v2.4\,q5-v2.4\,q50-v2.4\,q51-v2.4\,q52-v2.4\,q53-v2.4\,q54-v2.4\,q55-v2.4\,q56-v2.4\,q57-v2.4\,q58-v2.4\,q59-v2.4\,q6-v2.4\,q60-v2.4\,q61-v2.4\,q62-v2.4\,q63-v2.4\,q64-v2.4\,q65-v2.4\,q66-v2.4\,q67-v2.4\,q68-v2.4\,q69-v2.4\,q7-v2.4\,q70-v2.4\,q71-v2.4\,q72-v2.4\,q73-v2.4\,q74-v2.4\,q75-v2.4\,q76-v2.4\,q77-v2.4\,q78-v2.4\,q79-v2.4\,q8-v2.4\,q80-v2.4\,q81-v2.4\,q82-v2.4\,q83-v2.4\,q84-v2.4\,q85-v2.4\,q86-v2.4\,q87-v2.4\,q88-v2.4\,q89-v2.4\,q9-v2.4\,q90-v2.4\,q91-v2.4\,q92-v2.4\,q93-v2.4\,q94-v2.4\,q95-v2.4\,q96-v2.4\,q97-v2.4\,q98-v2.4\,q99-v2.4\,ss_max-v2.4"
