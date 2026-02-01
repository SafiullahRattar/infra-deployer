# ============================================================
# Stage 1: Build
# ============================================================
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

COPY app/go.mod app/go.sum ./
RUN go mod download

COPY app/ .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.version=$(git describe --tags --always 2>/dev/null || echo dev)" \
    -o /app/server .

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM scratch

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /app/server /server

EXPOSE 8080

USER 65534

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/server", "-healthcheck"]

ENTRYPOINT ["/server"]
