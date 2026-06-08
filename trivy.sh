#!/bin/bash

rm -rf .cache bom.cdx.json

docker run --rm \
  --dns 8.8.8.8 \
  -v $PWD/.cache/trivy:/root/.cache/ \
  aquasec/trivy:0.69.3 \
  image --download-db-only

docker run --rm \
  --network none \
  -v $PWD:/src \
  -v $PWD/.cache/trivy:/root/.cache/ \
  aquasec/trivy:0.69.3 \
  fs \
  --scanners vuln \
  --offline-scan \
  --skip-db-update \
  --skip-java-db-update \
  --format cyclonedx \
  --output /src/bom.cdx.json \
  /src
