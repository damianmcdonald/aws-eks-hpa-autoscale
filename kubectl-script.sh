#######################################################
# Kubernetes - Cheatsheets
#######################################################

# https://kubernetes.io/docs/reference/kubectl/cheatsheet/
# https://medium.com/faun/kubectl-commands-cheatsheet-43ce8f13adfb

#######################################################
# Demo commands - Hello World
#######################################################

# Deploy a pod in a Deployment
kubectl run hello-world --image=gcr.io/google-samples/hello-app:1.0

# Let's follow our pod and deployment status
# Deployments are made of ReplicaSets!
kubectl get deployment hello-world
kubectl get replicaset
kubectl get pods

# Expose the Deployment as a Serivce.
# This will create a Service for the ReplicaSet behind the Deployment
# We are exposing our serivce on port 80, connecting to an application running on 8080 in our pod.
# Port: Interal Cluster Port, the Service's port. You will point cluster resources here.
# TargetPort: The Pod's Serivce Port, your application. That one we defined when we started the pods.
kubectl expose deployment hello-world --port=80 --target-port=8080

# Check out the IP: and Port:, that's where we'll access this service.
kubectl get service hello-world

# Edit the service to assign a public IP address
kubectl edit service hello-world
# Asign a public IP Address
type: LoadBalancer

# Access the service inside the cluster
curl http://SERVICEIP:PORT

# We can edit the resources "on the fly" with kubectl edit. But this isn't reflected in our yaml. But is
# persisted in the etcd database...cluster store. Change 1 to 3.
kubectl edit deployment hello-world

# Get a list of the pods running
kubectl get pods

# Access the application again, try it several times, app will load balance.
curl http://SERVICEIP:PORT

kubectl delete service hello-world
kubectl delete deployment hello-world
kubectl get all

#######################################################
# HPA horizontal scaling
#######################################################

# install metrics api
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update
helm upgrade --install metrics-server stable/metrics-server

# verify install
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"

# deploy sample app
kubectl run php-apache --image=k8s.gcr.io/hpa-example --requests=cpu=500m --expose --port=80

# create an hpa group
kubectl autoscale deployment php-apache --cpu-percent=20 --min=1 --max=6

# verify the state of the hpa
kubectl get hpa

# watch the hpa scale
kubectl get hpa -w

### Open in new terminal ###

# generate load
kubectl run -i --tty load-generator --image=busybox /bin/sh
while true; do wget -q -O - http://php-apache; done

# clean up
kubectl delete hpa php-apache
kubectl delete service php-apache
kubectl delete deployment php-apache
kubectl delete deployment load-generator
helm uninstall metrics-server
kubectl get all


#######################################################
# Demo commands - Nginx scaleout
#######################################################

# deploy the autoscaler
kubectl apply -f kubernetes/cluster-autoscaler/cluster-autoscaler.yml

# check the logs for the autoscaler
kubectl logs -f deployment/cluster-autoscaler -n kube-system

# install nginx
kubectl apply -f kubernetes/nginx/deployment.yml

# check deployment
kubectl get deployment/nginx-to-scaleout

# scale out the cluster
kubectl scale --replicas=6 deployment/nginx-to-scaleout

# watch the scale out operation
kubectl get pods -o wide --watch

# view the cluster autoscaler logs
kubectl logs -f deployment/cluster-autoscaler -n kube-system

# clean up
kubectl delete deployment nginx-to-scaleout
kubectl get all