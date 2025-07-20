# ============================================================================
# BASE IMAGE SETUP
# ============================================================================

FROM ubuntu:noble

ENV PYTHON_VERSION=3.12 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/home/appuser/.local/bin:$PATH" \
    HOME=/home/appuser

# Set default shell to bash for RUN commands with pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ============================================================================
# SYSTEM PACKAGES INSTALLATION
# ============================================================================

# Update package lists and install required packages with updated pinned versions
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl=8.5.0-2ubuntu10.6 \
        jq=1.7.1-3build1 \
        git=1:2.43.0-1ubuntu7.3 \
        ca-certificates=20240203 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# TIMEZONE CONFIGURATION
# ============================================================================

# Set timezone environment variables
ENV TZ=UTC
ENV AIRFLOW__CORE__DEFAULT_TIMEZONE=UTC

# Link timezone data
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ >/etc/timezone

# ============================================================================
# WORKSPACE SETUP
# ============================================================================

# Set working directory
WORKDIR /app

# Create a non-root user and setup directories in one step
RUN useradd -m -s /bin/bash appuser \
    && mkdir -p /app/dags /app/tests \
    && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# ============================================================================
# UV (PYTHON PACKAGE MANAGER) INSTALLATION
# ============================================================================

# Install UV (Python package manager) and verify installation
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && SHELL=/bin/bash uv tool update-shell \
    && uv --version

# ============================================================================
# UV TOOLS INSTALLATION
# ============================================================================

# Install go-task tool and wait4x in consolidated steps
RUN uv tool install go-task-bin \
    && rm -rf /tmp/wait4x \
    && curl -LO https://github.com/wait4x/wait4x/releases/latest/download/wait4x-linux-amd64.tar.gz \
    && tar -xf wait4x-linux-amd64.tar.gz -C /tmp \
    && mkdir -p "$HOME"/.local/bin \
    && mv /tmp/wait4x "$HOME"/.local/bin/ \
    && export PATH="$HOME/.local/bin:$PATH" \
    && wait4x version \
    && rm -f wait4x-linux-amd64.tar.gz \
    && mkdir -p "$HOME"/.local/share/

# ============================================================================
# APACHE AIRFLOW SETUP
# ============================================================================

# Set up environment variables, create venv, and install Airflow
# hadolint ignore=SC1091
RUN AIRFLOW_VERSION="$(uv tool run --python="${PYTHON_VERSION}" --from=apache-airflow -- python -c "import airflow; print(airflow.__version__)")" \
    && echo "AIRFLOW_VERSION=$AIRFLOW_VERSION" \
    && uv venv --python="${PYTHON_VERSION}" \
    && . /app/.venv/bin/activate \
    && CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt" \
    && uv pip install "apache-airflow[cncf.kubernetes,celery]==${AIRFLOW_VERSION}" tzdata graphviz pandas --constraint "${CONSTRAINT_URL}"

# Create Airflow configuration file using heredoc
RUN cat <<EOF > airflow.cfg
[core]
auth_manager = airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager
executor = LocalExecutor
parallelism = 16
max_active_runs_per_dag = 16
default_timezone = UTC
EOF

ARG CACHE_BUST=1

# Initialize Airflow database and setup bash configuration
# hadolint ignore=SC1091
RUN . .venv/bin/activate \
    && airflow version \
    && airflow config get-value core auth_manager \
    && airflow db migrate \
    && airflow providers list \
    && echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >>"$HOME"/.bashrc \
    && echo "cd /app" >>"$HOME"/.bashrc \
    && echo ". /app/.venv/bin/activate" >>"$HOME"/.bashrc

# ============================================================================
# COPY PROJECT FILES
# ============================================================================

# Copy the entire project directory structure
COPY --chown=appuser:appuser . /app/

# Ensure e2e-test.sh is executable
RUN chmod +x /app/e2e-test.sh

# Default command
CMD ["/bin/bash"]
