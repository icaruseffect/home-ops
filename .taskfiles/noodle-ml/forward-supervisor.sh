#!/usr/bin/env bash
# Keeps `kubectl port-forward` to the ML tunnel pod alive and healthy.
# The forward process often stays up while every new stream times out
# ("Error creating error stream: Timeout occurred"); only a restart fixes that.
# So besides respawning on exit, probe the forwarded port and kill the forward
# after two failed probes in a row.
# Usage: forward-supervisor.sh <kube-context> <namespace> <local-port> <pidfile>
set -u
ctx=$1 ns=$2 port=$3 pidfile=$4
echo $$ > "$pidfile"
while true; do
  kubectl --context "$ctx" port-forward -n "$ns" deploy/noodle-ml-tunnel "$port:8080" &
  kp=$!
  fails=0
  while kill -0 "$kp" 2>/dev/null; do
    sleep 15
    if curl -s -o /dev/null -m 6 "http://127.0.0.1:$port"; then fails=0; else fails=$((fails + 1)); fi
    if [ "$fails" -ge 2 ]; then
      echo "$(date +%T) forward unhealthy ($fails failed probes), restarting"
      kill "$kp" 2>/dev/null
      break
    fi
  done
  wait "$kp" 2>/dev/null
  sleep 3
done
