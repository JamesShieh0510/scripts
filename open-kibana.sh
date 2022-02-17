
env=$1
if [ -z $env ]
then
    echo "Please input the environment name: "
    read env
fi
az aks get-credentials --resource-group OTSO-DEV --name $env

case $env in
    DEV)
        url='http://127.0.0.1:5601/goto/fa500012cb4f14351624f84be63c190f' #DEV
        ;;
    SFX-PROD)
        url='http://127.0.0.1:5601/goto/088b560f40a28ffc548d459fa95a7910' #SFX-PROD
        ;;
    *)
        echo "ERROR: the environment name is invalid."
        #exit 1
        ;;
esac

if [ ! -z $url ]
then
    open "$url"
    kubectl port-forward $(kubectl get pods -n kube-logging | grep kibana | awk '{print $1}') 5601:5601 -n kube-logging
fi
