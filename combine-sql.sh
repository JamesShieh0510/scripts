output_file=$1

if [ -z $output_file ]
then
    output_file='./result.sql'
fi

path_of_sql_files='./sql-files'
mkdir -p $path_of_sql_files

_list=($(ls -l $path_of_sql_files/*.sql |awk '{print $9}')) # for macOS
# _list=($(ls -l *.sql |awk '{print $9}')) # for ubuntu

rm -f $output_file
echo '' > $output_file

for file in $_list
do
    echo "writing sql from $file" 
    cat $file >> $output_file
done
