# Demo Setup

```bash
# cert-manager, net-certmanager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
kubectl wait --for=condition=Established --all crd
kubectl wait --for=condition=Available -n cert-manager --all deployments
kubectl create ns knative-serving
kubectl apply -f http://storage.googleapis.com/knative-nightly/net-certmanager/latest/net-certmanager.yaml

# serving
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/

# kourier
kubectl apply -f http://storage.googleapis.com/knative-nightly/net-kourier/latest/kourier.yaml

# config patches
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch "{\"data\":{\"172.17.0.100.sslip.io\":\"\"}}"
  
# Create curl pods for testing
kubectl create ns second
kubectl create ns first
kubectl apply -n first -f ../0-helpers/curl.yaml
kubectl apply -f ./yaml/ksvc.yaml

# setup cert-manager CA for rotation demo
kubectl delete -n cert-manager clusterissuer knative-selfsigned-issuer selfsigned-cluster-issuer
kubectl delete -n cert-manager certificate knative-selfsigned-ca

mkdir certs
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=TEST-ROOT-1/CN=TEST-ROOT-1' -keyout certs/root-1.key -out certs/root-1.crt
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=TEST-ROOT-2/CN=TEST-ROOT-2' -keyout certs/root-2.key -out certs/root-2.crt

kubectl cp certs/root-1.crt "first/$(kubectl get -n first pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/root-1.crt
kubectl cp certs/root-2.crt "first/$(kubectl get -n first pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/root-2.crt

# Store the first in a secret
kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-1.key \
    --cert=certs/root-1.crt --dry-run=client -o yaml | kubectl apply -f -
    
# Create the cluster CA issuer
kubectl apply -f ../8-trust-sources/poc-yaml/ca-issuer.yaml

# Point net-certmanager to use CA issuer
kubectl apply -f ../8-trust-sources/poc-yaml/config-certmanager.yaml
```