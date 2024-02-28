# Trusting CAs using projected volumes

## Motivation

* See discussion in https://github.com/knative/serving/pull/14717#discussion_r1473541048.
* Ideally, we want to support both [ClusterTrustBundles](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#cluster-trust-bundles) and plain Secrets/ConfigMaps.


## Basic functionality

* Leverages https://pkg.go.dev/crypto/x509#SystemCertPool
* Define env `SSL_CERT_DIR` AND `SSL_CERT_FILE`
* Mount multiple files to that directory using a `projected` volume


## How can a configuration look

### Example configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: activator
  namespace: knative-serving
spec:
  template:
    spec:
      containers:
      - name: activator
        env:
        - name: SSL_CERT_DIR
          value: /knative-ssl-dir
          
          # ⚠️ this can only be one, we need to use multiple folders
          # as only SSL_CERT_DIR can be a list
        - name: SSL_CERT_FILE 
          value: cm-trust-bundle.pem # this will only include one of the files from below

        volumeMounts:
          - mountPath: /knative-ssl-dir
            name: trust-bundles

      volumes:
        - name: trust-bundles
          projected:
            sources:
              - configMap:
                  name: "my-trust-bundle-cm"
                  items:
                    - key: "my-trust-bundle"
                      path: "cm-trust-bundle.pem"
                      
              - clusterTrustBundle:
                labelSelector:
                  matchLabels:
                    networking.knative.dev/trust-bundle: "true"
                path: "cluster-trust-bundle.pem"
                optional: "true"
```

## Where do we need the config

* Activator
* net-kourier controller
* net-istio controller

⚠️ The problem with the net-* controllers is, that they do not need the bundle on their system trust store, 
they need to configure their Envoy to use it. 

* example for [net-kourier](https://github.com/knative-extensions/net-kourier/pull/1171/files#diff-ba0933c476bd2d5262d8a049d818bfdb85e4367bd9fe4e44e6344e59d3245745R362)


## How can a user configure this?

### YAML installation

User can just (manually) edit the YAML with his installation tool/process/templating engine.

### Operator

⚠️ We'd need to build a config into `CommonSpec` to define `volumes` and `volumeMounts` in `workloads` to enable users to configure the bundles, as:

## Setup

```bash
# Cluster setup with feature gates and APIs enabled
kind create cluster --config=yaml/kind.yaml
kubectl cluster-info --context kind-kind
```

```bash
# make it available externally
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.11/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - 172.18.0.100-172.18.0.150
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

sudo ifconfig lo0 alias 172.18.0.100/24 up
```

```bash
# create two CAs to identify them later on the file system
mkdir certs
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=CLUSTER-BUNDLE/CN=CLUSTER-BUNDLE' -keyout certs/cluster-bundle-ca.key -out certs/cluster-bundle-ca.crt
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=CM/CN=CM' -keyout certs/cm-ca.key -out certs/cm-ca.crt
```

```bash
kubectl create ns knative-serving

# create cluster trust-bundle
certificate=$(cat certs/cluster-bundle-ca.crt)
sed "s|REPLACEME|$(echo "$certificate" | awk '{printf "    %s\\n", $0}')|" yaml/cluster-trust-bundle.yaml | kubectl apply -f -

# create a trust-bundle in a CM
# kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/cm-ca.crt
# intentionally do not label the bundle, so our existing code in net-kourier is not picking this up
```

```bash
# Deploy Serving
# in Serving repo
export KO_DOCKER_REPO=kind.local
git checkout cluster-trust-bundle
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/
```

```bash
# Deploy Kourier
kubectl apply -f http://storage.googleapis.com/knative-nightly/net-kourier/latest/kourier.yaml
```
```bash
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch "{\"data\":{\"172.18.0.100.sslip.io\":\"\"}}"
```

```bash
# install cert-manager & net-certmanager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
kubectl wait --for=condition=Established --all crd
kubectl wait --for=condition=Available -n cert-manager --all deployments
kubectl create ns knative-serving
kubectl apply -f http://storage.googleapis.com/knative-nightly/net-certmanager/latest/net-certmanager.yaml
```

```bash
# check for the certs
kubectl exec deploy/activator -n knative-serving -- cat /var/run/ko/knative-ssl-certs/cluster-trust-bundle.pem
```

```bash
# enable system-internal-tls
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"system-internal-tls":"enabled"}}'

# deploy a KSVC
kubectl create ns test
kubectl apply -n test -f ../0-helpers/curl.yaml
kubectl apply -f ./yaml/ksvc.yaml
```

## Testing

### Testing trust with `SelfSigned` cluster-issuer

```bash
# call the service from outside of the cluster
curl -i http://app.test.172.18.0.100.sslip.io
tls: failed to verify certificate: x509: certificate signed by unknown authority
```
```bash
# call the service from inside of the cluster via kourier
kubectl exec deployment/curl -n test -it -- curl -si http://app.test
tls: failed to verify certificate: x509: certificate signed by unknown authority
```
```bash
# call the service from inside of the cluster directly to activator
kubectl exec deployment/curl -n test -it -- curl -si http://activator-service.knative-serving:80 -H 'Knative-Serving-Namespace: test' -H 'Knative-Serving-Revision: app-00001'
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

```bash
# now let's put the SelfSigned CA from cert-manager in the ClusterTrustBundle
cmca=$(kubectl get secrets -n cert-manager knative-selfsigned-ca -o jsonpath={'.data.ca\.crt'} | base64 -d)
sed "s|REPLACEME|$(echo "$cmca" | awk '{printf "    %s\\n", $0}')|" yaml/cluster-trust-bundle.yaml | kubectl apply -f -
```

```bash
# check for the certs
kubectl exec deploy/activator -n knative-serving -- cat /var/run/ko/knative-ssl-certs/cluster-trust-bundle.pem | openssl x509 -text - | grep -E 'Subject:|Issuer|DNS' 
        Issuer: CN=knative.dev
        Subject: CN=knative.dev
```

```bash
# But unfortunately, this is not refreshed in activator:
{"severity":"INFO","timestamp":"2024-02-28T13:20:06.506368462Z","logger":"activator","caller":"certificate/cache.go:146","message":"updating system cert pool: 021\u00170\u0015\u0006\u0003U\u0004\n\u000c\u000eCLUSTER-BUNDLE1\u00170\u0015\u0006\u0003U\u0004\u0003\u000c\u000eCLUSTER-BUNDLE, ","commit":"a1ad60a-dirty","knative.dev/controller":"activator","knative.dev/pod":"activator-67cd797c8f-bkk9q"}
{"severity":"INFO","timestamp":"2024-02-28T13:20:11.502128763Z","logger":"activator","caller":"certificate/cache.go:146","message":"updating system cert pool: 021\u00170\u0015\u0006\u0003U\u0004\n\u000c\u000eCLUSTER-BUNDLE1\u00170\u0015\u0006\u0003U\u0004\u0003\u000c\u000eCLUSTER-BUNDLE, ","commit":"a1ad60a-dirty","knative.dev/controller":"activator","knative.dev/pod":"activator-67cd797c8f-bkk9q"}
```

⚠️ [from the docs](https://pkg.go.dev/crypto/x509#SystemCertPool)

> New changes in the system cert pool might not be reflected in subsequent calls. 

 