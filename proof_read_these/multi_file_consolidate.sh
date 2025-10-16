#!/bin/bash

# Script to compare multiple files and consolidate matching lines into a master file
# Usage: ./multi_file_consolidate.sh file1 file2 file3 ...

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
echo -e "${YELLOW}=== Multi-File Consolidation Tool ===${NC}\n"
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
    # Read unique lines from each file
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

# Ask which file to use as master
echo -e "${YELLOW}Which file do you want to use as the MASTER file?${NC}"
echo -e "${CYAN}(Duplicate lines will be removed from other files only if they exist in the master)${NC}\n"

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
        
        MASTER_INDEX=$((choice-1))
        MASTER_FILE="${FILES[$MASTER_INDEX]}"
        break
    else
        echo -e "${RED}Invalid choice. Please enter a number between 1 and $((NUM_FILES+1)).${NC}"
    fi
done

# Categorize duplicate lines
declare -a lines_in_master
declare -a lines_not_in_master

for line in "${duplicate_lines[@]}"; do
    IFS=',' read -ra file_indices <<< "${line_to_files["$line"]}"
    
    # Check if line is in master file
    in_master=false
    for idx in "${file_indices[@]}"; do
        if [ "$idx" -eq "$MASTER_INDEX" ]; then
            in_master=true
            break
        fi
    done
    
    if [ "$in_master" = true ]; then
        lines_in_master+=("$line")
    else
        lines_not_in_master+=("$line")
    fi
done

echo ""
echo -e "${YELLOW}=== Analysis ===${NC}"
echo -e "${GREEN}Lines that exist in master ($MASTER_FILE):${NC} ${#lines_in_master[@]}"
echo -e "${MAGENTA}Lines duplicated in other files but NOT in master:${NC} ${#lines_not_in_master[@]}"
echo ""

# Show what will happen to lines in master
if [ ${#lines_in_master[@]} -gt 0 ]; then
    echo -e "${CYAN}The following lines will be REMOVED from other files (kept in master):${NC}"
    for line in "${lines_in_master[@]}"; do
        echo -e "  - $line"
        IFS=',' read -ra file_indices <<< "${line_to_files["$line"]}"
        echo -e "    ${YELLOW}Will be deleted from:${NC}"
        for idx in "${file_indices[@]}"; do
            if [ "$idx" -ne "$MASTER_INDEX" ]; then
                echo -e "      • ${FILES[$idx]}"
            fi
        done
    done
    echo ""
fi

# Handle lines not in master
LINES_TO_ADD=()
if [ ${#lines_not_in_master[@]} -gt 0 ]; then
    echo -e "${MAGENTA}The following lines are duplicated across other files but NOT in master:${NC}"
    for line in "${lines_not_in_master[@]}"; do
        echo -e "  - $line"
        IFS=',' read -ra file_indices <<< "${line_to_files["$line"]}"
        echo -e "    ${YELLOW}Found in:${NC}"
        for idx in "${file_indices[@]}"; do
            echo -e "      • ${FILES[$idx]}"
        done
    done
    echo ""
    
    while true; do
        echo -e "${YELLOW}What do you want to do with these lines?${NC}"
        echo "1) Add them to master file and remove from others"
        echo "2) Leave them as is (no changes)"
        echo "3) Remove them from all files"
        read -p "Enter your choice (1-3): " dup_choice
        
        case $dup_choice in
            1)
                LINES_TO_ADD=("${lines_not_in_master[@]}")
                echo -e "${GREEN}Will add these lines to master and remove from others${NC}"
                break
                ;;
            2)
                echo -e "${CYAN}Will leave these lines unchanged${NC}"
                break
                ;;
            3)
                echo -e "${RED}Will remove these lines from all files${NC}"
                # Add to lines_in_master so they get deleted (but not added to master)
                for line in "${lines_not_in_master[@]}"; do
                    lines_in_master+=("$line")
                done
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}\n"
                ;;
        esac
    done
    echo ""
fi

# Show final summary
echo -e "${YELLOW}=== Summary ===${NC}"
echo -e "${GREEN}Master file:${NC} $MASTER_FILE"

if [ ${#LINES_TO_ADD[@]} -gt 0 ]; then
    echo -e "${GREEN}Lines to ADD to master:${NC} ${#LINES_TO_ADD[@]}"
fi

if [ ${#lines_in_master[@]} -gt 0 ]; then
    echo -e "${RED}Lines to REMOVE from other files:${NC} ${#lines_in_master[@]}"
    for idx in "${!FILES[@]}"; do
        if [ "$idx" -ne "$MASTER_INDEX" ]; then
            echo -e "  - ${FILES[$idx]}"
        fi
    done
fi

echo ""
read -p "Proceed with these changes? (yes/no): " confirmation

if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Operation cancelled. No changes made.${NC}"
    exit 0
fi

# Create files with lines to delete
> "$TEMP_DIR/lines_to_delete"
for line in "${lines_in_master[@]}"; do
    echo "$line" >> "$TEMP_DIR/lines_to_delete"
done
sort "$TEMP_DIR/lines_to_delete" > "$TEMP_DIR/lines_to_delete_sorted"

# Process each file (except master)
echo -e "\n${YELLOW}Processing files...${NC}\n"

for idx in "${!FILES[@]}"; do
    if [ "$idx" -eq "$MASTER_INDEX" ]; then
        continue
    fi
    
    file="${FILES[$idx]}"
    echo -e "  ${CYAN}Cleaning:${NC} $file"
    
    TEMP_OUTPUT="$TEMP_DIR/output_$idx"
    > "$TEMP_OUTPUT"
    
    # Read the file and filter out lines to delete
    while IFS= read -r line; do
        if ! grep -Fxq "$line" "$TEMP_DIR/lines_to_delete_sorted" 2>/dev/null; then
            echo "$line" >> "$TEMP_OUTPUT"
        fi
    done < "$file"
    
    # Replace original file
    mv "$TEMP_OUTPUT" "$file"
    echo -e "    ${GREEN}✓ Done${NC}"
done

# Add new lines to master if requested
if [ ${#LINES_TO_ADD[@]} -gt 0 ]; then
    echo -e "\n  ${CYAN}Adding lines to master:${NC} $MASTER_FILE"
    for line in "${LINES_TO_ADD[@]}"; do
        echo "$line" >> "$MASTER_FILE"
    done
    echo -e "    ${GREEN}✓ Done${NC}"
fi

echo -e "\n${GREEN}All files processed successfully!${NC}\n"

# Recalculate and display new hashes
echo -e "${YELLOW}Recalculated hashes:${NC}"
for file in "${FILES[@]}"; do
    display_hash "$file"
done

echo -e "\n${GREEN}=== Operation completed successfully ===${NC}"
