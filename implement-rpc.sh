#!/bin/bash

text=$(cat ./*/*.proto */*/*.proto 2>/dev/null | sed -rn 's/[[:space:]]+rpc [a-zA-Z]+\((.*)\) returns \((.*)\) \{\};/message \1 {\nmessage \2 {/p'
)

#The $'...' construct expands embedded ANSI escape sequences.
echo $"$text" > temp.txt
output=""
while read line; do
  target=$(cat ./*/*.proto */*/*.proto 2>/dev/null | grep "$line")
  if [ -z "$target" ]
  then
    output="$output\n$line\n\t\n}"
  fi
done < temp.txt
printf "$output\n"
rm temp.txt
