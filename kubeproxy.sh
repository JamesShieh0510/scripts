#!/bin/bash

#fetch .env file, and export all variables
set -a
source .env
set +a

# if $NAMESPACE is not set, then set it to default
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="default"
fi

rm -rf kube-proxy.yaml
cat <<EOF > ./kube-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-proxy
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-proxy
  template:
    metadata:
      labels:
        app: kube-proxy
    spec:
      containers:
      - name: alpine-curl
        image: alpine:latest
        command: ["sleep", "infinity"]
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        securityContext:
          privileged: true   # 將容器設置為特權容器
          runAsUser: 0 # 使用 root 使用者運行容器
EOF

proxy=$(kubectl get pod -n $NAMESPACE  | grep kube-proxy | awk '{print $1}')
# if proxy pod is not found, then create it
if [ -z "$proxy" ]; then
    echo "proxy pod is not found, creating it..."
    kubectl create -f kube-proxy.yaml
    #kubectl apply -f kube-proxy.yaml
fi
# if proxy pod status is Pending, then sleep 1 second then try until it is Running
proxy_pod_status=$(kubectl get pod -n $NAMESPACE  | grep kube-proxy | awk '{print $3}')
while [ "$proxy_pod_status" != "Running" ]; do
    proxy_pod_status=$(kubectl get pod -n $NAMESPACE  | grep kube-proxy | awk '{print $3}')
    echo "waiting for proxy pod to be Running..."
    sleep 3
done
proxy=$(kubectl get pod -n $NAMESPACE  | grep kube-proxy | awk '{print $1}')


# kubectl exec $proxy -n kube-logging -- apk add curl
kubectl exec $proxy -n $NAMESPACE -- $*
# kubectl exec $proxy -n kube-logging -- curl elasticsearch:9200

