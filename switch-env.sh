if [ "$(basename $(pwd))" != "local" ]; then
  mkdir -p local
  cd local
  if [ "$(basename $(pwd))" = "local" ] && [ ! -f "./config.ini" ]; then
    echo "ENV production" > ./config.ini
  fi
fi

_list=$(ls -ld $(find .) | grep local$ | awk '{print $9}')

env=$(cat ./config.ini | grep 'ENV' | awk '{print $2}') 

if [ "$env" = "localhost" ]; then
    echo "Switch setting to production."
    for _file in $_list
    do
        org_file=$(echo $_file | sed 's/.local//g')
        if [ -f "../$org_file.prod" ]; then
            mv "../$org_file.prod" "../$org_file"
        fi
    done
    echo 'ENV production' > ./config.ini
else
    echo "Switch setting to localhost."
    for _file in $_list
    do
        org_file=$(echo $_file | sed 's/.local//g')
        if [ ! -f "../$org_file.prod" ]; then
            mv "../$org_file" "../$org_file.prod"
            cp -f "$_file" "../$org_file"
        fi
    done
    echo 'ENV localhost' > ./config.ini

fi

cd ..


pb_path=$(ls | grep pb)  

if [ "$pb_path" != "" ]; then
  cd $pb_path
  protoc -I. -I../.. --gogo_out=plugins=grpc,paths=source_relative:. *.proto
  cd ..
fi

go mod tidy
go test ./...

