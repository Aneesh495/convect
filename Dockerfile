# syntax=docker/dockerfile:1
FROM python:3.11-slim AS builder

WORKDIR /app

# Install native compilation toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy repository source code
COPY . .

# Compile C spatial library
RUN make -C index clean && make -C index all

# Run complete test suite during build verification
RUN make test

# Production runtime container
FROM python:3.11-slim AS runner

WORKDIR /app

# Copy compiled binaries and source code
COPY --from=builder /app /app

ENV PYTHONPATH=/app
ENV CONVECT_ENV=production

# Expose streaming TCP ingest port
EXPOSE 9092

# Default CLI help
ENTRYPOINT ["python3", "cli/main.py"]
CMD ["--help"]
