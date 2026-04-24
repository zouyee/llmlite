# Stage 1: Build static binary targeting musl
FROM alpine:3.19 AS builder

RUN apk add --no-cache curl xz ca-certificates

RUN curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | \
    tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig

WORKDIR /app

ENV ZIG_GLOBAL_CACHE_DIR=/app/.zig-cache
ENV ZIG_LOCAL_CACHE_DIR=/app/.zig-cache

COPY build.zig ./
COPY build.zig.zon ./
COPY deps/ ./deps/
COPY src/ ./src/

# Ensure Zig cache subdirectories exist before build
RUN mkdir -p .zig-cache/tmp .zig-cache/p zig-pkg && \
    zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl

FROM scratch

COPY --from=builder /app/zig-out/bin/llmlite /llmlite

EXPOSE 8080

CMD ["/llmlite"]

FROM builder AS development

RUN apk add --no-cache git vim

WORKDIR /app

COPY . .
RUN mkdir -p .zig-cache/tmp .zig-cache/p zig-pkg && \
    ZIG_GLOBAL_CACHE_DIR=/app/.zig-cache ZIG_LOCAL_CACHE_DIR=/app/.zig-cache zig build

CMD ["/bin/sh"]

FROM development AS test

RUN test -f .env.test && cp .env.test .env || true

RUN mkdir -p .zig-cache/tmp .zig-cache/p zig-pkg
ENV ZIG_GLOBAL_CACHE_DIR=/app/.zig-cache
ENV ZIG_LOCAL_CACHE_DIR=/app/.zig-cache
CMD ["zig", "build", "test"]
