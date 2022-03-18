if [ "$(basename $(pwd))" != "local" ]; then
  cd local
fi

_list=($(ls -Rla | grep 'local$' | awk '{print $9}'))

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
