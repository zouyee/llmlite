FROM zig:0.15 AS builder

WORKDIR /

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN zig build

FROM alpine:3.19 AS runtime

RUN apk add --no-cache ca-certificates curl

WORKDIR /

COPY --from=builder /zig-out/bin/llmlite /
COPY --from=builder /src/*.zig /src/
COPY --from=builder /README.md /
COPY --from=builder /LICENSE /

CMD ["/llmlite"]

# Alternative: Development stage with full build tools
FROM builder AS development

RUN apt-get update && apt-get install -y \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /

COPY . .
RUN zig build

CMD ["/bin/sh"]

FROM development AS test

COPY .env.test .env 2>/dev/null || true

CMD ["zig", "build", "test"]
