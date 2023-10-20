#!/bin/sh

project_path=$1
doc_path=$2

cd $project_path
#go install github.com/swaggo/swag/cmd/swag@latest
swag init --parseDependency -g cmd/main.go --markdownFiles . --tags "webClient"
mv docs/swagger.yaml ../client.yaml
sed -i '' 's|// @host\t*.*|// @host\t\t\tapi.crm-admin.otso-dev.com|' cmd/main.go
sed -i '' 's|// @title\t*.*|// @title\t\t\tCRM Admin API|' cmd/main.go
sed -i '' 's|// @description\t*.*|// @description\tThis is the Documentation for the CRM Admin API.|' cmd/main.go

swag init --parseDependency -g cmd/main.go --markdownFiles . --tags "webAdmin"
sed -i '' 's|// @host\t*.*|// @host\t\t\tapi.crm.otso-dev.com|' cmd/main.go
sed -i '' 's|// @title\t*.*|// @title\t\t\tCRM Client API|' cmd/main.go
sed -i '' 's|// @description\t*.*|// @description\tThis is the Documentation for the CRM Client API.|' cmd/main.go

mv docs/swagger.yaml ../admin.yaml
mkdir ../client
find internal/controller/client -name "*.mdx" -type f -exec cp {} ../client/ \;
mkdir ../admin
find internal/controller/admin -name "*.mdx" -type f -exec cp {} ../admin/ \;

cd $doc_path
mv $project_path/../client.yaml static/api/client-v1.yaml
mv $project_path/../admin.yaml static/api/admin-v1.yaml
cp $project_path/../client/*.mdx docs/client-web-websocket/
cp $project_path/../admin/*.mdx docs/admin-web-websocket/
npm install --global yarn
yarn install
npm run start
