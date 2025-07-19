# List all available rules
default:
    @just --list

# Run Docker build and e2e test
test:
    just _build
    just _run

# Run Docker build with --no-cache and e2e test
test-no-cache:
    just _build-no-cache
    just _run

# Build Docker image
_build:
    docker build -t t .

# Build Docker image with --no-cache
_build-no-cache:
    docker build --no-cache -t t .

# Run e2e test in container
_run:
    docker run --rm -t t bash /app/e2e-test.sh
