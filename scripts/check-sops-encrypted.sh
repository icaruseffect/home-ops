#!/bin/sh
# Fail if a Kubernetes Secret manifest is not sops-encrypted.
rc=0
for f in "$@"; do
  if grep -qE '^kind: Secret[[:space:]]*$' "$f" && ! grep -q '^sops:' "$f"; then
    echo "unencrypted Secret: $f"
    rc=1
  fi
done
exit $rc
