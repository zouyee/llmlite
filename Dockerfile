# llmlite - Zig LLM SDK
# Build stage
FROM zig:0.15 AS builder

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . .

# Build the project
RUN zig build

# Runtime stage - minimal image
FROM alpine:3.19 AS runtime

# Install CA certificates for HTTPS
RUN apk add --no-cache ca-certificates curl

# Create non-root user
RUN adduser -D -g '' appuser

WORKDIR /app

# Copy build artifacts
COPY --from=builder /app/zig-out/bin/llmlite /app/
COPY --from=builder /app/src/*.zig /app/src/
COPY --from=builder /app/README.md /app/
COPY --from=builder /app/LICENSE /app/

# Change ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Default command
CMD ["/app/llmlite"]

# Alternative: Development stage with full build tools
FROM builder AS development

# Install additional development tools
RUN apt-get update && apt-get install -y \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy source and build
COPY . .
RUN zig build

# Default development command
CMD ["/bin/sh"]

# Stage for running tests
FROM development AS test

# Copy test environment file if exists
COPY .env.test .env 2>/dev/null || true

# Run tests
CMD ["zig", "build", "test"]
