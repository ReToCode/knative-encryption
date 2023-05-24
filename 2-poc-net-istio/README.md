# Setup

## Prerequisites
* Install `knative/serving`
* Install `knative-sandbox/net-istio`

## Configuration

```bash
# Install istio
istioctl install -y

# Use istio as networking layer
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"istio.ingress.networking.knative.dev"}}'

# Configure a domain
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"10.89.0.200.sslip.io":""}}'

# Enable internal encryption
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"internal-encryption":"true"}}'  
  
# Enable auto domain claims
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"autocreate-cluster-domain-claims":"true"}}'
  
# Deploy curl and workloads
kubectl apply -f ../curl.yaml 
kubectl apply -f ../curl-istio.yaml 
kubectl apply -f ../ksvc.yaml 

# Deploy kiali (optional)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/addons/kiali.yaml
```

## Debugging config
See https://github.com/istio/istio/wiki/Troubleshooting-Istio
```bash
# Analyzing the current config
istioctl analyze --log_output_level klog:none,cli:info

# Get current config of a istio proxy
istioctl proxy-config all istio-ingressgateway-6785fcd48-scdff -n istio-system  -o json

# Set proxy loglevels
istioctl proxy-config log deploy/istio-ingressgateway -n istio-system --level "debug"
```