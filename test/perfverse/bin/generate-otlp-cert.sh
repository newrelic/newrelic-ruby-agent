#!/usr/bin/env bash
set -euo pipefail

# Generates a self-signed cert for the local otlp_receiver sidecar (see
# test/perfverse/otlp_receiver/) so perf tests never send real profile data to an external
# OTLP destination. Not checked into the repo -- regenerated on demand into test/perfverse/certs/,
# shared as Docker build context by both the otlp_receiver and rails7 app images.

cert_dir="$(dirname "${BASH_SOURCE[0]}")/../certs"
mkdir -p "$cert_dir"
cd "$cert_dir"

if [[ -f otlp_localhost.crt && -f otlp_localhost.key ]]; then
  exit 0
fi

openssl req -x509 -newkey rsa:2048 -keyout otlp_localhost.key -out otlp_localhost.crt \
  -days 825 -nodes -subj "/CN=otlp-receiver" \
  -addext "subjectAltName=DNS:otlp-receiver,DNS:localhost,IP:127.0.0.1"
