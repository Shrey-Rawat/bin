#!/bin/bash

# Script to compare multiple files, find matching lines, and preserve them in selected file
# Usage: ./multi_file_compare.sh file1 file2 file3 ...

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
    echo -e "  ${BLUE}$file: ${GREEN}$hash${NC}"
}

# Check if at least 2 files provided
if [ "$#" -lt 2 ]; then
    echo -e "${RED}Error: Please provide at least two files as arguments${NC}"
    echo "Usage: $0 <file1> <file2> [file3] [file4] ..."
    exit 1
fi

# Store all files in an array
FILES=("$@")
NUM_FILES=${#FILES[@]}

# Check if all files exist
echo -e "${YELLOW}=== Multi-File Line Comparison Tool ===${NC}\n"
echo -e "${CYAN}Validating files...${NC}"

for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File '$file' does not exist${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} $file"
done

echo ""

# Calculate and display initial hashes
echo -e "${YELLOW}Initial hashes:${NC}"
for file in "${FILES[@]}"; do
    display_hash "$file"
done
echo ""

# Create temporary directory for processing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Create a map of line -> files containing that line
declare -A line_to_files
declare -A line_counts

echo -e "${YELLOW}Analyzing files for matching lines...${NC}\n"

# Process each file
for i in "${!FILES[@]}"; do
    file="${FILES[$i]}"
    # Read unique lines from each file (to avoid counting duplicates within same file multiple times)
    sort -u "$file" > "$TEMP_DIR/sorted_unique_$i"
    
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        # Add file index to the list of files containing this line
        if [ -z "${line_to_files["$line"]}" ]; then
            line_to_files["$line"]="$i"
            line_counts["$line"]=1
        else
            line_to_files["$line"]="${line_to_files["$line"]},$i"
            ((line_counts["$line"]++))
        fi
    done < "$TEMP_DIR/sorted_unique_$i"
done

# Find lines that appear in multiple files
declare -a duplicate_lines
for line in "${!line_counts[@]}"; do
    if [ "${line_counts["$line"]}" -gt 1 ]; then
        duplicate_lines+=("$line")
    fi
done

# Check if any duplicates found
if [ ${#duplicate_lines[@]} -eq 0 ]; then
    echo -e "${GREEN}No matching lines found across the files.${NC}"
    exit 0
fi

echo -e "${GREEN}Found ${#duplicate_lines[@]} line(s) that appear in multiple files:${NC}\n"
echo -e "${BLUE}========================================${NC}"

# Display duplicates with file information
line_number=1
for line in "${duplicate_lines[@]}"; do
    echo -e "${CYAN}[$line_number] Line:${NC} $line"
    
    # Show which files contain this line
    IFS=',' read -ra file_indices <<< "${line_to_files["$line"]}"
    echo -e "    ${YELLOW}Found in:${NC}"
    for idx in "${file_indices[@]}"; do
        echo -e "      - ${FILES[$idx]}"
    done
    echo ""
    ((line_number++))
done
echo -e "${BLUE}========================================${NC}\n"

# Ask which file to preserve lines in
echo -e "${YELLOW}In which file do you want to PRESERVE these matching lines?${NC}"
echo -e "${CYAN}(Lines will be DELETED from all other files that contain them)${NC}\n"

for i in "${!FILES[@]}"; do
    echo "$((i+1))) ${FILES[$i]}"
done
echo "$((NUM_FILES+1))) Cancel (exit without changes)"
echo ""

# Get user choice
while true; do
    read -p "Enter your choice (1-$((NUM_FILES+1))): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((NUM_FILES+1)) ]; then
        if [ "$choice" -eq $((NUM_FILES+1)) ]; then
            echo -e "${YELLOW}Operation cancelled. No changes made.${NC}"
            exit 0
        fi
        
        PRESERVE_INDEX=$((choice-1))
        PRESERVE_FILE="${FILES[$PRESERVE_INDEX]}"
        break
    else
        echo -e "${RED}Invalid choice. Please enter a number between 1 and $((NUM_FILES+1)).${NC}"
    fi
done

# Show which files will be modified
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo -e "  ${GREEN}PRESERVE lines in:${NC} $PRESERVE_FILE"
echo -e "  ${RED}DELETE matching lines from:${NC}"

FILES_TO_CLEAN=()
for i in "${!FILES[@]}"; do
    if [ $i -ne $PRESERVE_INDEX ]; then
        # Check if this file actually contains any of the duplicate lines
        has_duplicates=false
        for line in "${duplicate_lines[@]}"; do
            IFS=',' read -ra file_indices <<< "${line_to_files["$line"]}"
            for idx in "${file_indices[@]}"; do
                if [ "$idx" -eq "$i" ]; then
                    has_duplicates=true
                    break 2
                fi
            done
        done
        
        if [ "$has_duplicates" = true ]; then
            FILES_TO_CLEAN+=("$i")
            echo -e "    - ${FILES[$i]}"
        fi
    fi
done

if [ ${#FILES_TO_CLEAN[@]} -eq 0 ]; then
    echo -e "    ${CYAN}(None - selected file is the only one with these lines)${NC}"
    exit 0
fi

echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirmation

if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Operation cancelled. No changes made.${NC}"
    exit 0
fi

# Create a set of lines to delete (all duplicate lines)
echo "$TEMP_DIR/lines_to_delete"
printf "%s\n" "${duplicate_lines[@]}" > "$TEMP_DIR/lines_to_delete"
sort "$TEMP_DIR/lines_to_delete" > "$TEMP_DIR/lines_to_delete_sorted"

# Process each file that needs cleaning
echo -e "\n${YELLOW}Processing files...${NC}\n"

for file_idx in "${FILES_TO_CLEAN[@]}"; do
    file="${FILES[$file_idx]}"
    echo -e "  ${CYAN}Cleaning:${NC} $file"
    
    TEMP_OUTPUT="$TEMP_DIR/output_$file_idx"
    > "$TEMP_OUTPUT"  # Create empty file
    
    # Read the file and filter out duplicate lines
    while IFS= read -r line; do
        # Check if this line is in our duplicate list
        if ! grep -Fxq "$line" "$TEMP_DIR/lines_to_delete_sorted" 2>/dev/null; then
            echo "$line" >> "$TEMP_OUTPUT"
        fi
    done < "$file"
    
    # Replace original file
    mv "$TEMP_OUTPUT" "$file"
    echo -e "    ${GREEN}✓ Done${NC}"
done

echo -e "\n${GREEN}All files processed successfully!${NC}\n"

# Recalculate and display new hashes
echo -e "${YELLOW}Recalculated hashes:${NC}"
for file in "${FILES[@]}"; do
    display_hash "$file"
done

echo -e "\n${GREEN}=== Operation completed successfully ===${NC}"
