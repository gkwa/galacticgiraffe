#!/bin/bash
set -e

echo "🧪 E2E Test: Minimal Hello World DAG with JSON/jq parsing"

# 1. Copy DAG to Airflow
AIRFLOW_HOME=${AIRFLOW_HOME:-$HOME/airflow}
DAGS_FOLDER=${AIRFLOW__CORE__DAGS_FOLDER:-$AIRFLOW_HOME/dags}
mkdir -p "$DAGS_FOLDER"
cp dags/hello_world_dag.py "$DAGS_FOLDER/"
echo "✅ DAG copied"

# 2. Start scheduler if needed
if ! pgrep -f "airflow scheduler" >/dev/null; then
   nohup airflow scheduler >scheduler.log 2>&1 &
   echo "✅ Scheduler started"
   wait4x http http://127.0.0.1:8793
else
   echo "✅ Scheduler already running"
fi

# 3. Test DAG syntax
python3 "$DAGS_FOLDER/hello_world_dag.py"
echo "✅ DAG syntax valid"

# 4. Force DAG discovery
echo "🔄 Forcing DAG reserialization..."
airflow dags reserialize

# 5. Check DAG is loaded using JSON output
echo "🔍 Checking if DAG is discovered..."
DAG_EXISTS=$(airflow dags list -o json 2>/dev/null | jq -r '.[] | select(.dag_id == "hello_world_dag") | .dag_id' 2>/dev/null || echo "")

if [ "$DAG_EXISTS" = "hello_world_dag" ]; then
   echo "✅ DAG discovered"

   # Show DAG details
   airflow dags list -o json | jq -r '.[] | select(.dag_id == "hello_world_dag") | "DAG ID: \(.dag_id)\nPaused: \(.is_paused)\nFile: \(.fileloc)"'
else
   echo "❌ DAG still not found after reserialization"
   echo "📋 Available DAGs:"
   airflow dags list -o json | jq -r '.[] | .dag_id'
   exit 1
fi

# 6. Unpause DAG using JSON to check result
echo "🔓 Unpausing DAG..."
airflow dags unpause hello_world_dag >/dev/null

# Verify it's unpaused (Airflow 3.x uses "False" instead of "false")
IS_PAUSED=$(airflow dags list -o json | jq -r '.[] | select(.dag_id == "hello_world_dag") | .is_paused')
if [ "$IS_PAUSED" = "False" ]; then
   echo "✅ DAG unpaused successfully"
else
   echo "❌ Failed to unpause DAG (paused status: $IS_PAUSED)"
   exit 1
fi

# 7. Trigger DAG
echo "🎯 Triggering DAG..."
airflow dags trigger hello_world_dag >/dev/null

# 8. Poll for completion using JSON + jq
echo "⏳ Polling for completion..."
MAX_ATTEMPTS=24
attempt=0

while [ $attempt -lt $MAX_ATTEMPTS ]; do
   sleep 5
   attempt=$((attempt + 1))

   # Get the latest run state using jq
   LATEST_STATE=$(airflow dags list-runs hello_world_dag -o json 2>/dev/null | jq -r '.[0].state // "no_runs"' 2>/dev/null || echo "no_runs")

   echo "Attempt $attempt/$MAX_ATTEMPTS - Current state: $LATEST_STATE"

   if [ "$LATEST_STATE" = "success" ]; then
       echo "🎉 SUCCESS: DAG completed successfully in $((attempt * 5)) seconds!"

       # Show the successful run details using jq
       echo "📊 Run details:"
       airflow dags list-runs hello_world_dag -o json | jq -r '.[0] | "Run ID: \(.run_id)\nState: \(.state)\nStart: \(.start_date)\nEnd: \(.end_date)\nDuration: \(.run_duration // "N/A")s"'

       # Show task success count
       echo ""
       echo "📋 Task summary:"
       RUN_ID=$(airflow dags list-runs hello_world_dag -o json | jq -r '.[0].run_id')
       SUCCESSFUL_TASKS=$(airflow tasks states-for-dag-run hello_world_dag "$RUN_ID" -o json 2>/dev/null | jq -r '[.[] | select(.state == "success")] | length' 2>/dev/null || echo "0")
       TOTAL_TASKS=$(airflow tasks list hello_world_dag -o json 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
       echo "Tasks completed: $SUCCESSFUL_TASKS/$TOTAL_TASKS"

       echo ""
       echo "✅ E2E test PASSED!"
       exit 0

   elif [ "$LATEST_STATE" = "failed" ]; then
       echo "❌ FAILED: DAG failed after $((attempt * 5)) seconds"
       echo "📊 Failed run details:"
       airflow dags list-runs hello_world_dag -o json | jq -r '.[0] | "Run ID: \(.run_id)\nState: \(.state)\nStart: \(.start_date)\nEnd: \(.end_date)"'

       # Show failed tasks
       echo ""
       echo "📋 Failed tasks:"
       RUN_ID=$(airflow dags list-runs hello_world_dag -o json | jq -r '.[0].run_id')
       airflow tasks states-for-dag-run hello_world_dag "$RUN_ID" -o json 2>/dev/null | jq -r '.[] | select(.state == "failed") | "- \(.task_id): \(.state)"' 2>/dev/null || echo "No task details available"

       echo ""
       echo "❌ E2E test FAILED!"
       exit 1
   fi
done

echo "⏰ TIMEOUT: DAG did not complete within 2 minutes"
echo "📊 Final status:"
airflow dags list-runs hello_world_dag -o json | jq -r '.[0] | "Run ID: \(.run_id)\nState: \(.state)\nStart: \(.start_date)\nEnd: \(.end_date)"' 2>/dev/null || echo "No runs found"
echo "❌ E2E test TIMED OUT!"
exit 1
