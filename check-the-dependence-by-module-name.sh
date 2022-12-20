target_module=$1
if [ -z $target_module ]
then
    echo "Please input the module name you want to check (ex:s-user): "
    read target_module
fi
go mod tidy; 
version=$(cat go.mod | grep $target_module | awk '{print $2}');

module=$(go mod graph | grep " .*$target_module@$version" | awk '{print $1}')

echo "Which modules determined the version of $target_module :\n\n"
printf "\033[32m$module\033[0m"
echo "\n\n----------------------------------\n"

echo "all the modules that depend on $target_module are:\n\n"
go mod graph | grep " .*$target_module"
go mod graph | grep " .*$target_module@$version"
