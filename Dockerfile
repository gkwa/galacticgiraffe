# ============================================================================
# BASE IMAGE SETUP
# ============================================================================

# Use Ubuntu Noble (24.04) as the base image
FROM ubuntu:noble

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Add .local/bin to PATH for subsequent commands
ENV PATH="/home/appuser/.local/bin:$PATH"
ENV HOME=/home/appuser
ENV PYTHON_VERSION=3.12

# Set default shell to bash for RUN commands
SHELL ["/bin/bash", "-c"]

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
RUN useradd -m -s /bin/bash appuser

# ============================================================================
# TESTING SETUP (BEFORE USER SWITCH) - CREATE DIRECTORIES ONLY
# ============================================================================

# Create test directories for Airflow DAG testing (but don't copy files yet)
RUN mkdir -p /app/dags /app/tests

# Change ownership of entire /app directory to appuser
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# ============================================================================
# UV (PYTHON PACKAGE MANAGER) INSTALLATION
# ============================================================================

# Install UV (Python package manager) - using default installation directory
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Set up UV environment and verify installation
RUN SHELL=/bin/bash uv tool update-shell && \
   uv --version

# ============================================================================
# UV TOOLS INSTALLATION
# ============================================================================

# Install quicklizard tool from GitHub
RUN uv tool install go-task-bin

# Install wait4x
RUN rm -rf /tmp/wait4x && \
   curl -LO https://github.com/wait4x/wait4x/releases/latest/download/wait4x-linux-amd64.tar.gz && \
   tar -xf wait4x-linux-amd64.tar.gz -C /tmp && \
   mkdir -p $HOME/.local/bin && \
   mv /tmp/wait4x $HOME/.local/bin/ && \
   export PATH="$HOME/.local/bin:$PATH" && \
   wait4x version && \
   rm -f wait4x-linux-amd64.tar.gz

RUN mkdir -p $HOME/.local/share/

RUN git clone https://github.com/gkwa/ringgem $HOME/.local/share/ringgem

# ============================================================================
# APACHE AIRFLOW SETUP
# ============================================================================

# Set up environment variables and get Airflow version
RUN AIRFLOW_VERSION="$(uv tool run --python=${PYTHON_VERSION} --from apache-airflow -- python -c "import airflow; print(airflow.__version__)")" && \
   echo AIRFLOW_VERSION=$AIRFLOW_VERSION

# Create new virtual environment
RUN uv venv --python=${PYTHON_VERSION}

# Install Apache Airflow with dependencies
RUN AIRFLOW_VERSION="$(uv tool run --python=${PYTHON_VERSION} --from apache-airflow -- python -c "import airflow; print(airflow.__version__)")" && \
   source /app/.venv/bin/activate && \
   CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt" && \
   uv pip install "apache-airflow[cncf.kubernetes,celery]==${AIRFLOW_VERSION}" graphviz pandas --constraint "${CONSTRAINT_URL}"

# Create Airflow configuration file
RUN echo "[core]" > airflow.cfg && \
   echo "auth_manager = airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager" >> airflow.cfg && \
   echo "executor = LocalExecutor" >> airflow.cfg && \
   echo "parallelism = 16" >> airflow.cfg && \
   echo "max_active_runs_per_dag = 16" >> airflow.cfg

ARG CACHE_BUST=1

   # Initialize Airflow database and verify installation
RUN source .venv/bin/activate && \
   airflow version && \
   airflow config get-value core auth_manager && \
   airflow db migrate && \
   airflow providers list

# Ensure bash is available and create basic bash configuration
RUN echo export PATH=$HOME/.local/bin:'$PATH' >>$HOME/.bashrc && \
   echo cd /app >>/home/appuser/.bashrc && \
   echo source /app/.venv/bin/activate >>/home/appuser/.bashrc

# ============================================================================
# COPY TEST FILES LAST (FOR FAST ITERATION)
# ============================================================================

# Copy test files and set permissions (files are copied as appuser since we're already switched)
COPY --chown=appuser:appuser dags/hello_world_dag.py /app/dags/
COPY --chown=appuser:appuser e2e-test.sh /app/
RUN chmod +x /app/e2e-test.sh

# Default command
CMD ["/bin/bash"]

# Test command that can be run after container starts
# Usage: docker exec -it <container> /app/e2e-test.sh
