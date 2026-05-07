#!/usr/bin/env bash
# Build the Lambda deployment zip.
#
# pyarrow has compiled C extensions that must match Lambda's runtime
# (public.ecr.aws/lambda/python:3.11). We use Docker to build inside that image.
#
# Zipping is done via Python's stdlib zipfile module, so this script doesn't
# require the `zip` tool on the host (which is missing on default Windows Git Bash).

set -euo pipefail

cd "$(dirname "$0")"

rm -rf build ingest_gh_archive.zip
mkdir -p build

echo "==> Installing deps inside Lambda runtime image..."
docker run --rm \
    --entrypoint "" \
    -v "$PWD":/var/task \
    public.ecr.aws/lambda/python:3.11 \
    bash -c "pip install -r /var/task/requirements.txt -t /var/task/build && cp /var/task/handler.py /var/task/build/"

echo "==> Zipping with Python..."
# Try `python` first, fall back to `py` (Windows launcher) or `python3`.
PY=""
for cmd in python python3 py; do
    if command -v "$cmd" >/dev/null 2>&1; then
        PY="$cmd"
        break
    fi
done

if [ -z "$PY" ]; then
    echo "ERROR: no python interpreter found on PATH. Install Python or activate your venv." >&2
    exit 1
fi

"$PY" - <<'EOF'
import os, zipfile, sys

src = "build"
dst = "ingest_gh_archive.zip"

with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for root, _, files in os.walk(src):
        for name in files:
            full = os.path.join(root, name)
            # store with paths relative to the build/ root, so Lambda can find handler.py
            arcname = os.path.relpath(full, src)
            zf.write(full, arcname)

size_mb = os.path.getsize(dst) / 1e6
print(f"Wrote {dst} ({size_mb:.1f} MB)")
EOF

echo "==> Done."
