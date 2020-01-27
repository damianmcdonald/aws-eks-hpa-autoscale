#!/bin/bash

##############################################################
#                                                            #
# This sample demonstrates the following concepts:           #
#                                                            #
# * EKS Cluster creation                                     #
# * Use of eksctl cli                                        #
# * Creation and deployment of cluster autoscaler            #
# * Cleans up all the resources created                      #
#                                                            #
##############################################################

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variable declarations
REGION=$(aws configure get region --output text)
EKS_VERSION=1.14
CLUSTER_NAME=workshop
NODEGROUP_NAME=standard-workers
NODE_TYPE=t2.small
NODES_NUM=1
NODES_MIN=1
NODES_MAX=10
ASG_POLICY_NAME=ASG-Worker-Policy
CLUSTER_AUTOSCALER_FILE=$PWD/kubernetes/cluster-autoscaler/cluster-autoscaler.yml
AUTO_SCALING_POLICY_FILE=$PWD/kubernetes/cluster-autoscaler/cluster-policy.json
UNDEPLOY_FILE=aws-undeploy.sh

###########################################################
#                                                         #
# EKS cluster creation                                    #
#                                                         #
###########################################################

# Create the EKS cluster
echo -e "[${LIGHT_BLUE}INFO${NC}] Creating AWS EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
eksctl create cluster \
--name $CLUSTER_NAME \
--version $EKS_VERSION \
--region $REGION \
--nodegroup-name $NODEGROUP_NAME \
--node-type $NODE_TYPE \
--nodes $NODES_NUM \
--nodes-min $NODES_MIN \
--nodes-max $NODES_MAX \
--managed

echo -e "[${LIGHT_BLUE}INFO${NC}] Adding credentials to the AWS EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME

echo -e "[${LIGHT_BLUE}INFO${NC}] Describing the AWS EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
eksctl utils describe-stacks --region=$REGION --cluster=$CLUSTER_NAME

###########################################################
#                                                         #
# Create cluster-autoscaler.yml                           #
#                                                         #
###########################################################

# obtain the auto scaling group name
AUTO_SCALING_GROUP_NAME=$(aws autoscaling describe-auto-scaling-groups --max-items 1 --region $REGION | jq -r '.AutoScalingGroups | .[0] | .AutoScalingGroupName')

if [[ -z $AUTO_SCALING_GROUP_NAME ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain Auto Scaling Group Name for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

# delete any previous instance of cluster-autoscaler.yml
if [[ -f "$CLUSTER_AUTOSCALER_FILE" ]]; then
    rm $CLUSTER_AUTOSCALER_FILE
fi

cat > $CLUSTER_AUTOSCALER_FILE <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
- apiGroups: [""]
  resources: ["events","endpoints"]
  verbs: ["create", "patch"]
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/status"]
  verbs: ["update"]
- apiGroups: [""]
  resources: ["endpoints"]
  resourceNames: ["cluster-autoscaler"]
  verbs: ["get","update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["watch","list","get","update"]
- apiGroups: [""]
  resources: ["pods","services","replicationcontrollers","persistentvolumeclaims","persistentvolumes"]
  verbs: ["watch","list","get"]
- apiGroups: ["extensions"]
  resources: ["replicasets","daemonsets"]
  verbs: ["watch","list","get"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["watch","list"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["watch","list","get"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["watch","list","get"]

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["cluster-autoscaler-status"]
  verbs: ["delete","get","update"]

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - image: k8s.gcr.io/cluster-autoscaler:v1.2.2
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --nodes=1:4:$AUTO_SCALING_GROUP_NAME
          env:
            - name: AWS_REGION
              value: $REGION
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          imagePullPolicy: "Always"
      volumes:
        - name: ssl-certs
          hostPath:
            path: "/etc/ssl/certs/ca-bundle.crt"
EOF

###########################################################
#                                                         #
# Create and attach asg-policy.json                       #
#                                                         #
###########################################################

# obtain the EC2 instance id
INSTANCE_ID=$(aws ec2 describe-instances --region $REGION --filter Name=instance-state-name,Values=running | jq -r '.Reservations | .[0] | .Instances | .[0] | .InstanceId')

if [[ -z $INSTANCE_ID ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain Instance Id for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

IAM_PROFILE_ID=$(aws ec2 describe-instances --region $REGION --instance-id $INSTANCE_ID | jq -r '.Reservations | .[0] | .Instances | .[0] | .IamInstanceProfile.Id')

if [[ -z $IAM_PROFILE_ID ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain IAM profile Id for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

IAM_ROLE_NAME=$(aws iam list-instance-profiles --query "InstanceProfiles[?InstanceProfileId=='$IAM_PROFILE_ID'].Roles[0].RoleName" --output text)

if [[ -z $IAM_ROLE_NAME ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain IAM Role Name for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

# attach the policy
aws iam put-role-policy \
--role-name $IAM_ROLE_NAME \
--policy-name $ASG_POLICY_NAME \
--policy-document file://$AUTO_SCALING_POLICY_FILE

###########################################################
#                                                         #
# Undeployment file creation                              #
#                                                         #
###########################################################

# delete any previous instance of undeploy.sh
if [[ -f "$UNDEPLOY_FILE" ]]; then
    rm $UNDEPLOY_FILE
fi

# get the network interface id
NIC_ID=$(aws ec2 describe-network-interfaces | jq -r '.NetworkInterfaces | .[0] | .NetworkInterfaceId')

if [[ -z $NIC_ID ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain Network Interface ID for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

# get the network interface attachment id
ATTACHMENT_ID=$(aws ec2 describe-network-interfaces | jq -r '.NetworkInterfaces | .[0] | .Attachment.AttachmentId')

if [[ -z $ATTACHMENT_ID ]]; then
    echo -e "[${RED}FATAL${NC}] Could not obtain Attachment ID for EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
fi

cat > $UNDEPLOY_FILE <<EOF
#!/bin/bash

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo -e "[${LIGHT_BLUE}INFO${NC}] Detach Network Interface ${YELLOW}$ATTACHMENT_ID${NC} from EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID

echo -e "[${LIGHT_BLUE}INFO${NC}] Delete Network Interface ${YELLOW}$NIC_ID${NC} from EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
aws ec2 delete-network-interface --network-interface-id $NIC_ID

echo -e "[${LIGHT_BLUE}INFO${NC}] Delete the inline policy $ASG_POLICY_NAME from ${YELLOW}$IAM_ROLE_NAME${NC} ....";
aws iam delete-role-policy --role-name $IAM_ROLE_NAME --policy-name $ASG_POLICY_NAME

echo -e "[${LIGHT_BLUE}INFO${NC}] Terminating EKS cluster ${YELLOW}$CLUSTER_NAME${NC} ....";
eksctl delete cluster --name=$CLUSTER_NAME --region=$REGION
EOF

chmod +x $UNDEPLOY_FILE
