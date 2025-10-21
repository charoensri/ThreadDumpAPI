#!/bin/bash
#Run against DT1, 5 iterations, default 5-sec delay
#./threads-dump-v3.sh "https://comaus-acres-dt1.pega.net" Pega-web-6d9d95dd7f-ws7c9 5 "operator-pyIdentifier:password"
#Run against STG1, 10 iterations, with 4-sec:
#./threads-dump-v3.sh "https://comaus-acres-stg1.pega.net" pega-web-5f76988bfc-6z9hq 10 "operator-pyIdentifier:password" 4

# Check if user passed required arguments
if [ $# -lt 4 ]; then
  echo "Usage: $0 <base_url> <webnode> <number_of_iterations> <user:password> [delay_in_seconds]"
  exit 1
fi

base_url=$1
webnode=$2
iterations=$3
credentials=$4
delay=${5:-5}   # default to 5 seconds if not provided
count=0

# Ensure logs directory exists
logdir="logs"
mkdir -p "$logdir"

while [ $count -lt $iterations ]; do
  echo "Executing command (iteration $((count+1)) of $iterations)..."

  # Generate timestamp for filename
  currentDate=$(date +%Y%m%d)
  currentTime=$(date +%H%M%S)
  filename="${webnode}_${currentDate}_${currentTime}.zip"
  filepath="${logdir}/${filename}"

  echo "Saving curl output to: $filepath"

  # Run curl command
  curl  -u "$credentials" \
    "${base_url}/prweb/api/v1/nodes/${webnode}/diagnostics/thread_dump" \
    -o "$filepath"

  echo "Curl output saved successfully - $filepath"
  echo

  # Wait before next run
  sleep "$delay"

  count=$((count + 1))
done

# Compress all logs into a single tar.gz archive
archive_name="${webnode}_thread_dumps_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$archive_name" -C "$logdir" .

echo "Compressed archive created: $archive_name"

# Clean up individual log files
rm -rf "$logdir"/*

echo "Individual log files removed. Only archive remains."
