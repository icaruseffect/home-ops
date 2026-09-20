# Mounted at /usr/src/paperless/src/paperless/flowerconfig.py.
# paperless-ngx 3.2.0's s6 svc-flower unconditionally passes
# --conf=${PAPERLESS_SRC_DIR}/paperless/flowerconfig.py, and flower >= 2.1.0
# exits with FileNotFoundError when that file does not exist (the image stopped
# shipping one). Upstream fix (PR #14182, merged 2026-09-20) is not in any
# release yet - this file can be dropped once the fixed image ships.
# Defaults are fine: port 5555, broker from PAPERLESS_REDIS.
