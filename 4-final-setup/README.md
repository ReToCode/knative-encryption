# Final Setup: Knative internal encryption

This setup describes testing on the work for https://github.com/knative/serving/issues/13472 using [net-certmanager](https://github.com/knative-sandbox/net-certmanager).

## Setup

```bash
# Install cert-manager
kubectl apply -f ./third_party/cert-manager-latest/cert-manager.yaml
kubectl wait --for=condition=Established --all crd
kubectl wait --for=condition=Available -n cert-manager --all deployments

# Install serving (in serving directory)
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/

# Install kourier (in kourier directory)
ko apply -Rf config

# Enable kourier
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
  
# Set domain
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"10.89.0.200.sslip.io":""}}'

# Install net-certmanager (in net-certmanager directory)
ko apply -Rf config

# Apply net-certmanager config
kubectl apply -f ./config-certmanager.yaml
  
# Enable internal encryption
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"internal-encryption":"true"}}'

# Restart activator (for now needed)
kubectl delete pod -n knative-serving -l app=activator
```

## Deploy a Knative Service
```bash
kubectl apply -f ../0-helpers/ksvc.yaml
```

## Testing

### Preparation

```bash
# Create namespace and pods
kubectl create ns second
kubectl apply -n second -f ../0-helpers/curl.yaml
kubectl apply -n default -f ../0-helpers/curl.yaml

# Get CA and copy to curl pod
kubectl get secrets knative-internal-encryption-ca -n cert-manager -o jsonpath={'.data.ca\.crt'} | base64 -d | openssl x509 -text > ca.crt
kubectl cp ca.crt "default/$(kubectl get -n default pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
kubectl cp ca.crt "second/$(kubectl get -n second pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
rm ca.crt
```

```bash
./verify.sh
```

```text
☑️ Verifying internal encryption
☑️ Checking form same namespace

Calling http://helloworld
Call to http://helloworld succeeded

Calling http://helloworld.default
Call to http://helloworld.default succeeded

Calling http://helloworld.default.svc
Call to http://helloworld.default.svc succeeded

Calling http://helloworld.default.svc.cluster.local
Call to http://helloworld.default.svc.cluster.local succeeded

Calling https://helloworld
command terminated with exit code 35
Call to https://helloworld succeeded

Calling https://helloworld.default
# SSL result is:
*  subjectAltName: host "helloworld.default" matched cert's "helloworld.default"
Call to https://helloworld.default succeeded

Calling https://helloworld.default.svc
# SSL result is:
*  subjectAltName: host "helloworld.default.svc" matched cert's "helloworld.default.svc"
Call to https://helloworld.default.svc succeeded

Calling https://helloworld.default.svc.cluster.local
# SSL result is:
*  subjectAltName: host "helloworld.default.svc.cluster.local" matched cert's "helloworld.default.svc.cluster.local"
Call to https://helloworld.default.svc.cluster.local succeeded
☑️ Checking form other namespace

Calling http://helloworld
command terminated with exit code 6
Call to http://helloworld succeeded

Calling http://helloworld.default
Call to http://helloworld.default succeeded

Calling http://helloworld.default.svc
Call to http://helloworld.default.svc succeeded

Calling http://helloworld.default.svc.cluster.local
Call to http://helloworld.default.svc.cluster.local succeeded

Calling https://helloworld
command terminated with exit code 6
Call to https://helloworld succeeded

Calling https://helloworld.default
# SSL result is:
*  subjectAltName: host "helloworld.default" matched cert's "helloworld.default"
Call to https://helloworld.default succeeded

Calling https://helloworld.default.svc
# SSL result is:
*  subjectAltName: host "helloworld.default.svc" matched cert's "helloworld.default.svc"
Call to https://helloworld.default.svc succeeded

Calling https://helloworld.default.svc.cluster.local
# SSL result is:
*  subjectAltName: host "helloworld.default.svc.cluster.local" matched cert's "helloworld.default.svc.cluster.local"
Call to https://helloworld.default.svc.cluster.local succeeded

✅  All tests completed successfully
```
