

pb_path=$(ls | grep pb)  

if [ "$pb_path" != "" ]; then
  cd $pb_path
  protoc -I. -I../.. --gogo_out=plugins=grpc,paths=source_relative:. *.proto
  cd ..
fi

go mod tidy
go test ./...
