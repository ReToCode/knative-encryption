# Setup

## Prerequisites
* Install `Knative Serving`
* Install `net-istio`

## Configuration

```bash
# Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-core.yaml

# A networking layer
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.8.1/kourier.yaml
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# Configure a domain
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"172.18.255.200.sslip.io":""}}'

# Cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
```