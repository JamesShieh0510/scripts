#!/bin/bash

# function to get name or description for a given tag and value
get_field_value() {
    local tag=$1
    local value=$2
    ./find-fix-api-meaning.sh "$XML_PATH" "$tag" "$value"
}

# main function to process the log file
process_log() {
    while IFS= read -r line; do
        # Trim trailing "|"
        line=${line%|}
        # split the line by "|"
        tokens=()
        IFS='|' read -ra tokens <<< "$line"
        
        # iterate over tokens and replace
        for token in "${tokens[@]}"; do
            IFS='=' read -r tag value <<< "$token"
            
            # get name and description
            name_desc=$(get_field_value "$tag" "$value")
            
            # if name_desc has Description, use it, otherwise use original value
            if echo "$name_desc" | grep -q 'Description:' ; then
                name=$(echo "${name_desc}" | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
                description=$(echo "${name_desc}" | awk -F': ' '{print $4}')
            else
                name=$(echo "${name_desc}" | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
                description="$value"
            fi
            
            # print results
            echo -n "$name=$description|"
        done
        
        # print separator
        echo -e "\n----------------"
    done < "$LOG_PATH"
}


XML_PATH=$1
LOG_PATH=$2

strings $LOG_PATH > ./temp_txt.log
LOG_PATH=./temp_txt.log
process_log
