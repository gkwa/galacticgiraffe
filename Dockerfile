# ============================================================================
# BASE IMAGE SETUP
# ============================================================================

# Use Ubuntu Noble (24.04) as the base image
FROM ubuntu:noble

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Add .local/bin to PATH for subsequent commands
ENV PATH="$HOME/.local/bin:$PATH"

ENV HOME=/home/appuser

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
RUN useradd -m -s /bin/bash appuser && chown -R appuser:appuser /app

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
    uv tool install go-task-bin'

# Install wait4x
RUN rm -rf /tmp/wait4x && \
    curl -LO https://github.com/wait4x/wait4x/releases/latest/download/wait4x-linux-amd64.tar.gz && \
    tar -xf wait4x-linux-amd64.tar.gz -C /tmp && \
    mkdir -p $HOME/.local/bin && \
    mv /tmp/wait4x $HOME/.local/bin/ && \
    export PATH="$HOME/.local/bin:$PATH" && \
    wait4x version && \
    rm -f wait4x-linux-amd64.tar.gz

RUN bash -c 'source $HOME/.local/bin/env && \
    git clone https://github.com/gkwa/ringgem $HOME/.local/share/ringgem'

# ============================================================================
# APACHE AIRFLOW SETUP
# ============================================================================

# Set up environment variables and get Airflow version
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    PYTHON_VERSION=3.12 && \
    AIRFLOW_VERSION="$(uv tool run --python=${PYTHON_VERSION} --from apache-airflow -- python -c "import airflow; print(airflow.__version__)")" && \
    echo AIRFLOW_VERSION=$AIRFLOW_VERSION'

# Clean up any existing environment
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    rm -rf .venv && \
    rm -rf airflow/'

# Create new virtual environment
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    PYTHON_VERSION=3.12 && \
    uv venv --python=${PYTHON_VERSION}'

# Install Apache Airflow with dependencies
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    PYTHON_VERSION=3.12 && \
    AIRFLOW_VERSION="$(uv tool run --python=${PYTHON_VERSION} --from apache-airflow -- python -c "import airflow; print(airflow.__version__)")" && \
    source .venv/bin/activate && \
    CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt" && \
    uv pip install "apache-airflow[cncf.kubernetes,celery]==${AIRFLOW_VERSION}" graphviz pandas --constraint "${CONSTRAINT_URL}"'

# Create Airflow configuration file
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    echo "[core]" > airflow.cfg && \
    echo "auth_manager = airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager" >> airflow.cfg && \
    echo "executor = LocalExecutor" >> airflow.cfg && \
    echo "parallelism = 16" >> airflow.cfg && \
    echo "max_active_runs_per_dag = 16" >> airflow.cfg'

ARG CACHE_BUST=1

    # Initialize Airflow database and verify installation
RUN bash -c 'source $HOME/.local/bin/env && \
    set -e && \
    source .venv/bin/activate && \
    airflow version && \
    airflow config get-value core auth_manager && \
    airflow db migrate && \
    airflow providers list'

# ============================================================================
# CONTAINER STARTUP
# ============================================================================

# Default command
CMD ["/bin/bash"]
