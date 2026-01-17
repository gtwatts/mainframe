#!/usr/bin/env bash
# MAINFRAME Demo Script
# Demonstrates UUID, JSON, progress bar, and email validation

# Source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

echo "=== MAINFRAME Demo ==="
echo

# 1) Generate a UUID
echo "1. Generating UUID..."
my_uuid=$(uuid)
echo "   UUID: $my_uuid"
echo

# 2) Create JSON with UUID and timestamp
echo "2. Creating JSON object..."
current_ts=$(timestamp)
# json_object expects key=value pairs
json_data=$(json_object \
    "id=$my_uuid" \
    "created_at=$current_ts" \
    "source=mainframe_demo")
echo "   JSON: $json_data"
echo

# 3) Show a progress bar
echo "3. Progress bar demo..."
for i in {1..10}; do
    progress_bar "$i" 10 30  # current, total, width
    sleep 0.1
done
echo

# 4) Validate email addresses
echo "4. Email validation..."
test_emails=("gordon@example.com" "invalid-email" "test@domain.co.uk" "no@dots")

for email in "${test_emails[@]}"; do
    if is_valid_email "$email"; then
        echo "   $email -> VALID"
    else
        echo "   $email -> INVALID"
    fi
done

echo
echo "=== Demo Complete ==="
