#!/bin/bash

# Script to compare two files, show matching lines, and delete them from selected file
# Usage: ./compare_and_clean.sh file1 file2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to calculate hash
calculate_hash() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# Function to display hash
display_hash() {
    local file="$1"
    local hash=$(calculate_hash "$file")
    echo -e "${BLUE}Hash of $file: ${GREEN}$hash${NC}"
}

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Error: Please provide exactly two files as arguments${NC}"
    echo "Usage: $0 <file1> <file2>"
    exit 1
fi

FILE1="$1"
FILE2="$2"

# Check if both files exist
if [ ! -f "$FILE1" ]; then
    echo -e "${RED}Error: File '$FILE1' does not exist${NC}"
    exit 1
fi

if [ ! -f "$FILE2" ]; then
    echo -e "${RED}Error: File '$FILE2' does not exist${NC}"
    exit 1
fi

echo -e "${YELLOW}=== File Comparison Tool ===${NC}\n"

# Calculate and display initial hashes
echo -e "${YELLOW}Initial hashes:${NC}"
display_hash "$FILE1"
display_hash "$FILE2"
echo ""

# Find matching lines
echo -e "${YELLOW}Finding matching lines...${NC}\n"

# Sort both files and find common lines
TEMP_SORTED1=$(mktemp)
TEMP_SORTED2=$(mktemp)
TEMP_MATCHES=$(mktemp)

sort "$FILE1" > "$TEMP_SORTED1"
sort "$FILE2" > "$TEMP_SORTED2"

# Find common lines
comm -12 "$TEMP_SORTED1" "$TEMP_SORTED2" > "$TEMP_MATCHES"

MATCH_COUNT=$(wc -l < "$TEMP_MATCHES")

if [ "$MATCH_COUNT" -eq 0 ]; then
    echo -e "${GREEN}No matching lines found between the two files.${NC}"
    rm "$TEMP_SORTED1" "$TEMP_SORTED2" "$TEMP_MATCHES"
    exit 0
fi

echo -e "${GREEN}Found $MATCH_COUNT matching line(s):${NC}\n"
echo -e "${BLUE}----------------------------------------${NC}"
cat -n "$TEMP_MATCHES"
echo -e "${BLUE}----------------------------------------${NC}\n"

# Ask which file to delete from
while true; do
    echo -e "${YELLOW}From which file do you want to delete these matching lines?${NC}"
    echo "1) $FILE1"
    echo "2) $FILE2"
    echo "3) Cancel (exit without changes)"
    read -p "Enter your choice (1, 2, or 3): " choice
    
    case $choice in
        1)
            TARGET_FILE="$FILE1"
            break
            ;;
        2)
            TARGET_FILE="$FILE2"
            break
            ;;
        3)
            echo -e "${YELLOW}Operation cancelled. No changes made.${NC}"
            rm "$TEMP_SORTED1" "$TEMP_SORTED2" "$TEMP_MATCHES"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}\n"
            ;;
    esac
done

# Confirmation
echo ""
echo -e "${RED}WARNING: This will delete $MATCH_COUNT line(s) from $TARGET_FILE${NC}"
read -p "Are you sure you want to proceed? (yes/no): " confirmation

if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Operation cancelled. No changes made.${NC}"
    rm "$TEMP_SORTED1" "$TEMP_SORTED2" "$TEMP_MATCHES"
    exit 0
fi

# Delete matching lines from target file
echo -e "\n${YELLOW}Deleting matching lines from $TARGET_FILE...${NC}"

TEMP_OUTPUT=$(mktemp)

# Read the matches into an array for exact matching
declare -A matches_map
while IFS= read -r line; do
    matches_map["$line"]=1
done < "$TEMP_MATCHES"

# Filter out matching lines
while IFS= read -r line; do
    if [[ ! -v matches_map["$line"] ]]; then
        echo "$line" >> "$TEMP_OUTPUT"
    fi
done < "$TARGET_FILE"

# Replace original file with cleaned version
mv "$TEMP_OUTPUT" "$TARGET_FILE"

echo -e "${GREEN}✓ Matching lines deleted successfully!${NC}\n"

# Recalculate and display new hashes
echo -e "${YELLOW}Recalculated hashes:${NC}"
display_hash "$FILE1"
display_hash "$FILE2"

# Cleanup
rm "$TEMP_SORTED1" "$TEMP_SORTED2" "$TEMP_MATCHES"

echo -e "\n${GREEN}=== Operation completed successfully ===${NC}"
