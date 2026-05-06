#!/usr/bin/env bash
# Build the Lambda deployment zip.
#
# pyarrow has compiled C extensions that must match Lambda's runtime
# (public.ecr.aws/lambda/python:3.11). We use Docker to build inside that image.

set -euo pipefail

cd "$(dirname "$0")"

rm -rf build *.zip
mkdir -p build

echo "==> Installing deps inside Lambda runtime image..."
docker run --rm \
    --entrypoint "" \
    -v "$PWD":/var/task \
    public.ecr.aws/lambda/python:3.11 \
    bash -c "pip install -r /var/task/requirements.txt -t /var/task/build && cp /var/task/handler.py /var/task/build/"

cd build
echo "==> Zipping..."
zip -r9 ../ingest_gh_archive.zip . > /dev/null
cd ..

echo "==> Built ingest_gh_archive.zip ($(du -h ingest_gh_archive.zip | cut -f1))"
