cat ./*/*.proto */*/*.proto 2>/dev/null | sed -rn 's/[[:space:]]+rpc [a-zA-Z]+\((.*)\) returns \((.*)\) \{\};/message \1 {\n}\nmessage \2 {\n}/p'
