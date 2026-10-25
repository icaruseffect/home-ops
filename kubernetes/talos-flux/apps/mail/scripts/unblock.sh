#!/bin/bash

# Define server URL
SERVER_URL="http://mail.example.com:8080"
#CRED=""

echo "Fetching blocked IPs..."
#blocked_ips=$(./stalwart-cli -u $SERVER_URL -c $CRED server list-config server.blocked-ip | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
blocked_ips=$(stalwart-cli server list-config server.blocked-ip | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
security_blocked_ips=$(stalwart-cli server list-config security.ip-blocked | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')

# Debugging: Show extracted IPs
echo "Extracted IPs:"
echo "$blocked_ips"

# Check if any IPs were found
if [[ -z "$blocked_ips" ]]; then
  echo "No blocked IPs found."
  exit 0
fi

# Parallel execution using xargs - change '4' to the number of parallel runs you want - I used 25 no problem
#echo "$blocked_ips" | xargs -I {} -P 4 ./stalwart-cli -u $SERVER_URL -c $CRED server delete-config server.blocked-ip.{}
echo "$blocked_ips" | xargs -I {} -P 4 stalwart-cli server delete-config server.blocked-ip.{}
echo "$security_blocked_ips" | xargs -I {} -P 4 stalwart-cli server delete-config security.ip-blocked.{}

echo "All IPs have been unblocked."
