# https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html
# https://eksctl.io/introduction/getting-started/
# https://eksworkshop.com/scaling/deploy_ca/

# Install eksclient
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /home/he-man/Downloads
sudo mv /home/he-man/Downloads/eksctl /usr/local/bin
eksctl version

# Installing aws-iam-authenticator
curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator


eksctl utils describe-stacks --region=eu-west-1 --cluster=workshop
#eksctl utils write-kubeconfig --cluster=<name> [--kubeconfig=<path>][--set-kubeconfig-context=<bool>]
eksctl utils write-kubeconfig --cluster=workshop
