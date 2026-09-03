#!/usr/bin/env bash

current_date=$(date)
host_name=$(hostname)
user_name=$(whoami)
output_directory="system-info-output"

read -p "Enter a name for this system report: " report_name
report_name=${report_name:-system-report}
process_file="$output_directory/${report_name}-processes.txt"

mkdir -p "$output_directory"
touch "$process_file"
ps aux > "$process_file"

echo "System Information"
echo "=================="
echo "Date: $current_date"
echo "Hostname: $host_name"
echo "Username: $user_name"
echo
echo "Disk Usage:"
df -h
echo
echo "Running Processes:"
ps aux
echo
echo "Process information saved to: $process_file"