# PoC: Setup with net-certmanager to generate cluster.local services

## Setup
```bash
kubectl apply -f https://github.com/knative/net-certmanager/releases/download/knative-v1.9.0/release.yaml
kubectl apply -f ./cert-manager-config
```

