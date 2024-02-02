# Cert-manager only solution

```bash
# install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
kubectl wait --for=condition=Established --all crd
kubectl wait --for=condition=Available -n cert-manager --all deployments

# install istio
istioctl install -y

# install net-certmanager (in net-certmanager directory)
git checkout upstream/main
ko apply -f config

# Install serving (in serving directory)
git checkout encryption-certmanager-only
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/

# Install net-istio (in net-istio directory)
git checkout cluster-local-tls
ko apply -Rf config
  
# Set domain
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch "{\"data\":{\"172.17.0.100.sslip.io\":\"\"}}"
    
# Part 1: Enable cluster-local-domain-tls encryption
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"cluster-local-domain-tls":"enabled"}}'

# Part 2: External domains
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"external-domain-tls":"enabled"}}'

# Part 3: wildcard certs (unrelated to encryption)
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"external-domain-tls":"enabled"}}'
kubectl patch --namespace knative-serving configmap config-network -p '{"data": {"namespace-wildcard-cert-selector": "{\"matchExpressions\": [{\"key\":\"networking.knative.dev/disableWildcardCert\", \"operator\": \"NotIn\", \"values\":[\"true\"]}]}"}}'
```

## Deploy a Knative Service
```bash
# external service
kubectl apply -f ../0-helpers/ksvc.yaml

# cluster-local service
kubectl apply -f ../0-helpers/ksvc-cluster-local.yaml
```

## Testing

### Preparation

```bash
# Create namespace and pods
kubectl create ns second
kubectl apply -n second -f ../0-helpers/curl.yaml
kubectl apply -n default -f ../0-helpers/curl.yaml

# Get CA and copy to curl pod
kubectl get secrets knative-selfsigned-ca -n cert-manager -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text > /tmp/ca.crt
kubectl cp /tmp/ca.crt "default/$(kubectl get -n default pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
kubectl cp /tmp/ca.crt "second/$(kubectl get -n second pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
```

### Verify with SNI

Just for manual testing:

```bash
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default --cacert /tmp/ca.crt
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default.svc --cacert /tmp/ca.crt
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default.svc.cluster.local --cacert /tmp/ca.crt
kubectl run openssl --rm -n default --image=alpine/openssl --restart=Never -it --command -- sh -c "echo | openssl s_client -connect helloworld.default.svc.cluster.local:443 | openssl x509 -text"
```

```bash
# Verify cluster-external-domain
curl -si --cacert /tmp/ca.crt https://helloworld.default.172.17.0.100.sslip.io
```

### Verify with traffic tags

```bash
kubectl apply -f ../0-helpers/ksvc-traffic-tags.yaml
kubectl exec deployment/curl -n default -it -- curl -si https://latest-helloworld.default --cacert /tmp/ca.crt
curl -si --cacert /tmp/ca.crt https://latest-helloworld.default.172.17.0.100.sslip.io
```

### Verify with domain-mapping and TLS

```bash
kubectl apply -f ../0-helpers/ksvc-domainmapping-tls.yaml
curl -si --cacert /tmp/ca.crt https://helloworld.default.172.17.0.100.sslip.io
curl -si --cacert /tmp/ca.crt https://helloworld-dm.default.172.17.0.100.sslip.io
```

### Verify with script 

Automated testing with multiple cases:

```bash
./verify.sh
```

```text
📝 Verifying cluster-local-domain-tls
📝 Checking form same namespace

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
📝 Checking form other namespace

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
