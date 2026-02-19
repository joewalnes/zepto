# syntax=docker/dockerfile:1
# Dockerfile example with various instructions

# Build stage
FROM golang:1.21-alpine AS builder

# Labels
LABEL maintainer="developer@example.com"
LABEL version="1.0"
LABEL description="Multi-stage build example"

# Arguments
ARG APP_VERSION=1.0.0
ARG BUILD_DATE

# Environment variables
ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

# Working directory
WORKDIR /app

# Copy dependency files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags="-s -w -X main.Version=${APP_VERSION}" \
    -o /app/server ./cmd/server

# Production stage
FROM alpine:3.18 AS production

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata && \
    adduser -D -g '' appuser

# Copy binary from builder
COPY --from=builder /app/server /usr/local/bin/server
COPY --from=builder --chown=appuser:appuser /app/config /etc/app/config

# Set user
USER appuser

# Expose port
EXPOSE 8080/tcp
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Volume for data
VOLUME ["/data", "/logs"]

# Entry point and command
ENTRYPOINT ["/usr/local/bin/server"]
CMD ["--config", "/etc/app/config/app.yaml"]

# Alternative shell form
# CMD /usr/local/bin/server --config /etc/app/config/app.yaml

# Development stage
FROM builder AS development

# Install dev tools
RUN apk add --no-cache git vim

# Different working directory for dev
WORKDIR /workspace

# Mount source for live reload
# VOLUME /workspace

# Override entrypoint for dev
ENTRYPOINT ["go", "run", "."]

# Testing stage
FROM builder AS testing

RUN go test -v ./...

# Onbuild example
ONBUILD COPY . /app
ONBUILD RUN go build -o /app/main .

# Stop signal
STOPSIGNAL SIGTERM

# Shell instruction
SHELL ["/bin/bash", "-c"]
