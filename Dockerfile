# Stage 1: Build static binary targeting musl
FROM alpine:3.19 AS builder

RUN apk add --no-cache curl xz

RUN curl -L https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz | \
    tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.15.2/zig /usr/local/bin/zig

WORKDIR /app

COPY build.zig ./
COPY src/ ./src/

RUN zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl

FROM scratch

COPY --from=builder /app/zig-out/bin/llmlite /llmlite

EXPOSE 8080

CMD ["/llmlite"]

FROM builder AS development

RUN apk add --no-cache git vim

WORKDIR /app

COPY . .
RUN zig build

CMD ["/bin/sh"]

FROM development AS test

RUN test -f .env.test && cp .env.test .env || true

CMD ["zig", "build", "test"]
