cd *pb 2>/dev/null
cd ./protobuffer/ 2>/dev/null

folders=$(ls -d */) 2>/dev/null
for folder in $folders
do
    cd $folder
    protoc -I.  -I../.. -I../../.. --gogo_out=plugins=grpc,paths=source_relative:. *.proto
    cd ..
done
protoc -I.  -I../.. -I../../.. --gogo_out=plugins=grpc,paths=source_relative:. *.proto 2>/dev/null
cd ../
