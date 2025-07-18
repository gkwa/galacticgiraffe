# ============================================================================
# BASE IMAGE SETUP
# ============================================================================

# Use Ubuntu Noble (24.04) as the base image
FROM ubuntu:noble

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# SYSTEM PACKAGES INSTALLATION
# ============================================================================

# Update package lists and install required packages
RUN apt-get update && \
    apt-get install -y \
        curl \
        jq \
        git \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# WORKSPACE SETUP
# ============================================================================

# Set working directory
WORKDIR /app

# Create a non-root user (optional but recommended for security)
RUN useradd -m -s /bin/bash appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# ============================================================================
# UV (PYTHON PACKAGE MANAGER) INSTALLATION
# ============================================================================

# Install UV (Python package manager) - using default installation directory
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    echo 'source $HOME/.local/bin/env' >> ~/.bashrc

# Set up UV environment and verify installation
RUN bash -c 'source $HOME/.local/bin/env && \
    SHELL=/bin/bash uv tool update-shell && \
    uv --version'

# ============================================================================
# UV TOOLS INSTALLATION
# ============================================================================

# Install quicklizard tool from GitHub
RUN bash -c 'source $HOME/.local/bin/env && \
    uv tool install https://github.com/gkwa/quicklizard/archive/refs/heads/master.zip'

# Verify quicklizard installation
RUN bash -c 'source $HOME/.local/bin/env && \
    quicklizard -v'

# ============================================================================
# TASK RUNNER OPERATIONS
# ============================================================================

# Install wait4x using task runner in ringgem directory
RUN bash -c 'source $HOME/.local/bin/env && \
    task --dir=/root/.local/share/ringgem/ringgem-master install-wait4x-on-linux'

# ============================================================================
# APACHE AIRFLOW SETUP
# ============================================================================

# Set up Apache Airflow environment
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    PYTHON_VERSION=3.12 && \
    AIRFLOW_VERSION="$(uv tool run --python=${PYTHON_VERSION} --from apache-airflow -- python -c "import airflow; print(airflow.__version__)")" && \
    echo AIRFLOW_VERSION=$AIRFLOW_VERSION && \
    \
    # Clean up any existing environment \
    rm -rf .venv && \
    rm -rf airflow/ && \
    \
    # Create new virtual environment \
    uv venv --python=${PYTHON_VERSION} && \
    \
    # Activate environment and install Airflow \
    source .venv/bin/activate && \
    CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt" && \
    uv pip install "apache-airflow[cncf.kubernetes,celery]==${AIRFLOW_VERSION}" graphviz pandas --constraint "${CONSTRAINT_URL}" && \
    \
    # Create Airflow configuration \
    cat > airflow.cfg <<EOF && \
[core] \
auth_manager = airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager \
executor = LocalExecutor \
parallelism = 16 \
max_active_runs_per_dag = 16 \
EOF \
    \
    # Initialize Airflow \
    airflow version && \
    airflow config get-value core auth_manager && \
    airflow db migrate && \
    airflow providers list'

# ============================================================================
# CONTAINER STARTUP
# ============================================================================

# Default command
CMD ["/bin/bash"]