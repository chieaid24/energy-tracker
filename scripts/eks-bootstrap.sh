#!/usr/bin/env bash
set -euo pipefail

# EKS cluster addon bootstrap script.
# Run after `terraform apply` and `aws eks update-kubeconfig`.
# Requires: helm, kubectl, aws CLI configured for the correct account.

CLUSTER_NAME="iot-tracker-dev"
REGION="us-east-1"
ACCOUNT_ID="714454206433"
VPC_ID="vpc-0f217f3adb70f565f"
ROUTE53_ZONE_ID="Z050509095PF9UEA4RVL"
DOMAIN="energy.aidanchien.com"

echo ">>> Creating gp3 StorageClass..."
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite

echo ">>> Adding Helm repos..."
helm repo add eks https://aws.github.io/eks-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo add external-secrets https://charts.external-secrets.io
helm repo add jetstack https://charts.jetstack.io
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

echo ">>> Installing AWS Load Balancer Controller..."
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-alb-controller" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID"

echo ">>> Installing ingress-nginx..."
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type=nlb" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme=internet-facing" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type=ip" \
  --set controller.ingressClassResource.default=true

echo ">>> Installing ExternalDNS..."
helm install external-dns external-dns/external-dns \
  -n external-dns --create-namespace \
  --set provider.name=aws \
  --set policy=upsert-only \
  --set registry=txt \
  --set txtOwnerId="$CLUSTER_NAME" \
  --set "domainFilters[0]=$DOMAIN" \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-external-dns" \
  --set "sources[0]=ingress" \
  --set "sources[1]=service"

echo ">>> Installing External Secrets Operator..."
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-external-secrets"

echo ">>> Installing cert-manager..."
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-cert-manager"

echo ">>> Installing metrics-server..."
helm install metrics-server metrics-server/metrics-server -n kube-system

echo ">>> Waiting for pods to be ready..."
sleep 30

echo ">>> Creating ClusterSecretStore..."
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: $REGION
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF

echo ">>> Creating ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: route53-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: chieaid24@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          route53:
            region: $REGION
            hostedZoneID: $ROUTE53_ZONE_ID
        selector:
          dnsZones:
            - $DOMAIN
EOF

echo ">>> Bootstrap complete. Verify with:"
echo "    kubectl get pods -A | grep -v Running"
echo "    kubectl get clustersecretstore"
echo "    kubectl get clusterissuer"
echo "    kubectl top nodes"
