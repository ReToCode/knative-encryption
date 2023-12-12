# PoC of trusting CA bundles

## Prerequisites

Setup according to [7-cert-manager-only](../7-cert-manager-only/README.md)

## net-kourier

```bash
# happy cases
kubectl apply -f poc-yaml/signer-cm.yaml
kubectl apply -f poc-yaml/trust-manager-cm.yaml
kubectl apply -f poc-yaml/newline-cm.yaml

# invalid cases
kubectl apply -f poc-yaml/broken-invalid-cert-cm.yaml
kubectl apply -f poc-yaml/broken-notcert-cm.yaml
kubectl apply -f poc-yaml/broken-partially-valid-cert-cm.yaml
```

```bash
# Get routing-serving-certs
kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.ca\.crt'} | base64 -d | openssl x509 -text

# Get Envoy config
kubectl apply -f poc-yaml/envoy-bootstrap-dump.yaml
kubectl delete kourier-system deploy/3scale-kourier-gateway
kubectl port-forward -n kourier-system deploy/3scale-kourier-gateway 9000

curl localhost:9000/config_dump | jq -r '.configs[1].dynamic_active_clusters[0].cluster.transport_socket.typed_config.common_tls_context.validation_context.trusted_ca.inline_bytes' | base64 -d
```

```bash
curl -k http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!
```

## Full Test Set with Rotation

### Initial setup

```bash
kubectl create ns knative-serving

# nightly net-certmanager
kubectl apply -f https://raw.githubusercontent.com/knative/serving/main/third_party/cert-manager-latest/net-certmanager.yaml

# Install serving (in serving directory)
git checkout trust-bundle
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/

# Install kourier (in kourier directory)
git checkout trust-bundle
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
  --patch "{\"data\":{\"172.17.0.100.sslip.io\":\"\"}}"
```

### Using a manual CA issuer

```bash
# Drop selfsigned CA and secret
kubectl delete -n cert-manager clusterissuer knative-selfsigned-issuer selfsigned-cluster-issuer
kubectl delete -n cert-manager certificate knative-selfsigned-ca

# Create two CAs
mkdir certs
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=TEST-ROOT-1/CN=TEST-ROOT-1' -keyout certs/root-1.key -out certs/root-1.crt
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=TEST-ROOT-2/CN=TEST-ROOT-2' -keyout certs/root-2.key -out certs/root-2.crt

# Store the first in a secret
kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-1.key \
    --cert=certs/root-1.crt --dry-run=client -o yaml | kubectl apply -f -

# Create the cluster CA issuer
kubectl apply -f poc-yaml/ca-issuer.yaml

# Point net-certmanager to use CA issuer
kubectl apply -f poc-yaml/config-certmanager.yaml

# Enable system-internal-tls
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"system-internal-tls":"enabled"}}'
kubectl delete pod -n knative-serving -l app=activator --grace-period=0 --force

# Verify
kubectl get secrets routing-seving-certs -n knative-serving -o yaml
```

### Create Knative Services

```bash
# Create a Knative Service
kubectl apply -f ../0-helpers/ksvc.yaml
kubectl apply -f poc-yaml/ksvc-other-namespace.yaml

# Verify
kubectl get secrets -A | grep serving-certs

demo              serving-certs                   kubernetes.io/tls   3      5m50s
knative-serving   routing-serving-certs           kubernetes.io/tls   3      5m49s
default           serving-certs                   kubernetes.io/tls   3      5m48s
```

### Test rotation without trust-bundle

```bash
# Initial position, calling the Knative Service will work fine, 
# as our components trust the `ca.crt` in the Secret
curl http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!

# Update the CA secret to the second CA
kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-2.key \
    --cert=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -
    
# Force renewal of the certificate of the Knative Service in `default` namespace
kubectl delete secret -n default serving-certs
kubectl delete certificate -n default serving-certs

# Verify that the certificate is now signed by root-2
kubectl get secrets serving-certs -n default -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text
Issuer: O=TEST-ROOT-2, CN=TEST-ROOT-2

kubectl get secrets serving-certs -n demo -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text
Issuer: O=TEST-ROOT-1, CN=TEST-ROOT-1

# The two `serving-certs` are now signed by different CAs. Activator will trust the first CA, but not the second one.

# Verify
curl http://helloworld.default.172.17.0.100.sslip.io
tls: failed to verify certificate: x509: certificate signed by unknown authority

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!
```

### Test rotation with trust-bundle

```bash
# Add the first CA to a trust-bundle
kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/root-1.crt
kubectl label cm/my-trust-bundle -n knative-serving knative-ca-trust-bundle="true"

# As root-2 is not trusted yet, still not working:
curl http://helloworld.default.172.17.0.100.sslip.io
tls: failed to verify certificate: x509: certificate signed by unknown authority

# Update the trust-bundle to include the seconds CA
kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/root-1.crt --from-file=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -

# Verify that now both services work
curl http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!

# Force renewal of the certificate of the Knative Service in `demo` namespace
kubectl delete secret -n demo serving-certs
kubectl delete certificate -n demo serving-certs

# Verify that the certificate is now signed by root-2
kubectl get secrets serving-certs -n default -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text
Issuer: O=TEST-ROOT-2, CN=TEST-ROOT-2

kubectl get secrets serving-certs -n demo -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text
Issuer: O=TEST-ROOT-2, CN=TEST-ROOT-2

# Verify
curl http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!

# Remove the root-1 CA from the trust bundle
kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -

# Verify
curl http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!

# We can also remove the trust bundle completely, but this will again break, 
# as the `routing-serving-certs` secret is not yet updated. As soon as we force the update there, the `ca.crt`
# is updated to root-2 CA, and this is going to work again.
kubectl delete cm -n knative-serving my-trust-bundle

# Verify
curl http://helloworld.default.172.17.0.100.sslip.io
tls: failed to verify certificate: x509: certificate signed by unknown authority

curl http://helloworld.demo.172.17.0.100.sslip.io
tls: failed to verify certificate: x509: certificate signed by unknown authority

kubectl delete secret -n knative-serving routing-serving-certs
kubectl delete certificate -n knative-serving routing-serving-certs

kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text
Issuer: O=TEST-ROOT-2, CN=TEST-ROOT-2

curl http://helloworld.default.172.17.0.100.sslip.io
Hello Go Sample v1!

curl http://helloworld.demo.172.17.0.100.sslip.io
Hello Go Sample v1!
```

### Cleanup

```bash
# Cleanup
kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-1.key \
    --cert=certs/root-1.crt --dry-run=client -o yaml | kubectl apply -f -

kubectl delete ksvc --all -A
kubectl delete kcert --all -A
kubectl delete cert --all -A
kubectl delete secret serving-certs -n default
kubectl delete secret serving-certs -n demo
kubectl delete secret routing-serving-certs -n knative-serving

kubectl delete cm -n knative-serving my-trust-bundle

kubectl delete pod -n knative-serving -l app=activator --grace-period=0 --force
kubectl delete pod -n knative-serving -l app=net-kourier-controller --grace-period=0 --force
kubectl delete pod -n kourier-system --all --grace-period=0 --force

# we are back at ROOT-1 CA
kubectl apply -f ~/code/knative/serving/config/core/300-knativecertificate.yaml
```
