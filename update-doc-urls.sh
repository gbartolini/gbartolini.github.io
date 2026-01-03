#!/bin/bash

TARGET_DIR="content/posts"

# Verify directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR not found."
    exit 1
fi

echo "Updating documentation version..."

# Perform the replacement
find "$TARGET_DIR" -type f -exec sed -i 's|/docs/1.28/|/docs/1.29/|g' {} +

echo "Done."
