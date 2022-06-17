echo "//generate from script\n"
text=$(cat ./*/*.proto */*/*.proto 2>/dev/null | sed -rn 's/[[:space:]]+rpc [a-zA-Z]+\((.*)\) returns \((.*)\) \{\};/message \1 {\nmessage \2 {/p'
)
echo $text > temp
output=""
cat temp | while read line 
do
  target=$(cat ./*/*.proto */*/*.proto 2>/dev/null | grep "$line") 
  if [ -z $target ]
  then
    output="$output\n$line\n\t\n}"
  fi
done
echo $output
rm temp

