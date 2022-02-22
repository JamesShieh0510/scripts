
env=$1
if [ -z $env ]
then
    echo "Please input the environment name: "
    read env
fi
az aks get-credentials --resource-group OTSO-DEV --name $env

case $env in
    DEV)
        url='http://127.0.0.1:3000' #DEV
        ;;
    SFX-PROD)
        url='http://127.0.0.1:3000' #SFX-PROD
        ;;
    *)
        url="http://127.0.0.1:3000"
        #exit 1
        ;;
esac

#bash <(curl -s https://raw.githubusercontent.com/JamesShieh0510/scripts/master/open-grafana.sh SFX-PROD)


if [ ! -z $url ]
then
    open "$url"
    kubectl port-forward service/grafana 3000 -n kube-monitoring
fi
