# Stage 1: Build static binary targeting musl
FROM alpine:3.19 AS builder

RUN apk add --no-cache curl xz

# Install Zig
RUN curl -L https://ziglang.org/download/0.15.0/zig-linux-x86_64-0.15.0.tar.xz | \
    tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-linux-x86_64-0.15.0/zig /usr/local/bin/zig

WORKDIR /app

COPY build.zig build.zig.zon* ./
COPY src/ src/

# Build targeting musl for static linking (recommended for containers)
RUN zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl

# Stage 2: Minimal scratch image with just the binary (~1-3MB)
FROM scratch

COPY --from=builder /app/zig-out/bin/llmlite /llmlite

EXPOSE 8080

CMD ["/llmlite"]

# Development stage with full build tools
FROM builder AS development

RUN apk add --no-cache git vim

WORKDIR /app

COPY . .
RUN zig build

CMD ["/bin/sh"]

# Test stage
FROM development AS test

COPY .env.test .env 2>/dev/null || true

CMD ["zig", "build", "test"]
