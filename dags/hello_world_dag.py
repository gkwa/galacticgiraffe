import datetime
import airflow
import airflow.providers.standard.operators.bash
import airflow.providers.standard.operators.python
import airflow.utils.timezone

default_args = {
    "start_date": airflow.utils.timezone.datetime(2024, 1, 1),
}

dag = airflow.DAG(
    "hello_world_dag",
    default_args=default_args,
    description="A simple hello world DAG",
    schedule=datetime.timedelta(days=1),
    catchup=False,
    tags=["example", "hello_world"],
)


def print_hello():
    print("Hello World from Python!")
    return "Hello World task completed successfully"


hello_python_task = airflow.providers.standard.operators.python.PythonOperator(
    task_id="hello_python",
    python_callable=print_hello,
    dag=dag,
)

hello_bash_task = airflow.providers.standard.operators.bash.BashOperator(
    task_id="hello_bash",
    bash_command='echo "Hello World from Bash!"',
    dag=dag,
)

hello_python_task >> hello_bash_task
