#!/bin/sh
# Non-modifying terraform format check; falls back to tofu if terraform is absent.
bin=terraform
command -v terraform >/dev/null 2>&1 || bin=tofu
exec "$bin" fmt -check -diff "$@"
