#!/bin/bash

awk -v num="$2" '
BEGIN { 
    quote="'"'"'";
    found=0;
}  

$0 ~ "<field number='\''" num "'\''" {
    capture=1;
    match($0, /name='\''([^'\'']+)'\''/);
    name = substr($0, RSTART+6, RLENGTH-7);
    match($0, /type='\''([^'\'']+)'\''/);
    type = substr($0, RSTART+6, RLENGTH-7);
}

capture && /<value/ {
    match($0, /enum='\''([^'\'']+)'\''/);
    enum = substr($0, RSTART+6, RLENGTH-7);
    match($0, /description='\''([^'\'']+)'\''/);
    if (RLENGTH > 0) {
        description = substr($0, RSTART+13, RLENGTH-14);
    }
    if(enum == target) {
        print "Name: " name ", Type: " type ", Description: " description;
        found = 1;
        exit;  
    }
}

/<\/field>/ { 
    capture=0; 
}

END {
    if(!found) {
        print "Name: " name ", Type: " type;
    }
}
' target="$3" $1
