#!/bin/bash

package=$(cat ./*/*.proto */*/*.proto 2>/dev/null | sed -rn 's/^package[[:space:]]([a-zA-Z]+);$/\1/p' | awk 'NR==1{print $1}')
text=$(cat ./*/*.proto */*/*.proto 2>/dev/null | sed -rn 's/[[:space:]]+rpc ([a-zA-Z]+)\((.*)\) returns \((.*)\) \{\};/func (s *Server) \1(ctx context.Context, req *'$package'.\2) (*'$package'.\3, error) {/p'
)

#The $'...' construct expands embedded ANSI escape sequences.
echo $"$text" > temp.txt
output=""
while read line; do
  target=$(cat ./*.go ./*/*.go */*/*.go 2>/dev/null | grep -F "$line")
  if [ -z "$target" ]
  then
    return_str=$(echo $line | sed -rn 's/^func.*\(.*\(.*\(.*\*(.*),.*/\treturn \&\1\{\}, nil/p')
    output="$output\n$line\n\t\n$return_str\n}"
   
  fi
done < temp.txt
printf "$output\n"
rm temp.txt
