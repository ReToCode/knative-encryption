# Serverless auto-tls and internal-encryption

## Prerequisites
* A `kubernetes` cluster with `kubectl` configured that can provide services with type `LoadBalancer`
* Installed the following components:

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

## Use Case 1: Enable auto-tls on ingress
```bash
# Install net-certmanager
kubectl apply -f https://github.com/knative/net-certmanager/releases/download/knative-v1.8.1/release.yaml

# Apply configuration
kubectl apply -f ./cert-manager-config
kubectl apply -f ./tls-on-ingress

# Deploy a ksvc
kubectl apply -f ksvc.yaml

# Test using curl
curl -ikv https://helloworld.default.172.18.255.200.sslip.io

* Server certificate:
*  subject: CN=helloworld.default.172.18.255.200.sslip.io
*  start date: Jan 20 09:07:55 2023 GMT
*  expire date: Apr 20 09:07:55 2023 GMT
*  issuer: CN=helloworld.default.172.18.255.200.sslip.io
Hello Go Sample v1!
* Connection #0 to host helloworld.default.172.18.255.200.sslip.io left intact
```

## Use Case 2: Enable internal encryption
```bash
kubectl apply -f ./internal-encryption

# Force restart activator pods to open https listener
kubectl delete pod -n knative-serving -l app=activator
kubectl wait --timeout=60s --for=condition=Available deployment -n knative-serving activator

# Deploy a ksvc
kubectl apply -f ksvc.yaml

### Testing
### [Outside] -> [Ingress controller] 
# Using curl from outside of the cluster will still return 
# the ingress certificate (see use case 1 above) that is hosted by the ingress controller
curl -ikv https://helloworld.default.172.18.255.200.sslip.io

* Server certificate:
*  subject: CN=helloworld.default.172.18.255.200.sslip.io
*  start date: Jan 20 09:07:55 2023 GMT
*  expire date: Apr 20 09:07:55 2023 GMT
*  issuer: CN=helloworld.default.172.18.255.200.sslip.io
Hello Go Sample v1!
* Connection #0 to host helloworld.default.172.18.255.200.sslip.io left intact

### [Ingress controller] -> [Activator]
# The requests are re-encrypted on the ingress-controller
kubectl get king helloworld -n default -o yaml
# The kingress points to port 443 on the helloworld-00001 service
# using an internal TLS certificate that is stored in the 'default' namespace
│     http:                                                                                                                                                                                          │
│       paths:                                                                                                                                                                                       │
│       - splits:                                                                                                                                                                                    │
│         - appendHeaders:                                                                                                                                                                           │
│             Knative-Serving-Namespace: default                                                                                                                                                     │
│             Knative-Serving-Revision: helloworld-00001                                                                                                                                             │
│           percent: 100                                                                                                                                                                             │
│           serviceName: helloworld-00001                                                                                                                                                            │
│           serviceNamespace: default                                                                                                                                                                │
│           servicePort: 443 
│     visibility: ExternalIP                                                                                                                                                                         │
│   tls:                                                                                                                                                                                             │
│   - hosts:                                                                                                                                                                                         │
│     - helloworld.default.172.18.255.200.sslip.io                                                                                                                                                   │
│     secretName: route-f2959f4d-3688-4785-898c-e9ad9e3e6392  

# The activator will returns its certificate
curl -ivk https://helloworld-00001.default.svc.cluster.local
* Server certificate:
*  subject: O=knative.dev; CN=control-plane
*  start date: Jan 20 08:59:37 2023 GMT
*  expire date: Feb 19 08:59:37 2023 GMT
*  issuer: O=knative.dev; CN=control-plane

# The certificate of the activator is located in the knative-serving namespace
kubectl get secret -n knative-serving
NAME                            TYPE     DATA   AGE
knative-serving-certs           Opaque   3      60m # Certificate for Subject: O=knative.dev, CN=control-plane
serving-certs-ctrl-ca           Opaque   2      60m # CA for Subject: O=knative.dev, CN=control-plane

### [Activator] -> [KService with QProxy]
# The queue-proxy reads its certificate from the secret `default-serving-certs`
kubectl get deployment helloworld-00001-deployment -n default -o yaml > deployment.yaml
      volumes:
      - name: server-certs
        secret:
          defaultMode: 420
          secretName: default-serving-certs

curl -ivk https://helloworld-00001-private.default.svc.cluster.local
* Server certificate:
*  subject: O=knative.dev; CN=control-plane
*  start date: Jan 20 09:14:41 2023 GMT
*  expire date: Feb 19 09:14:41 2023 GMT
*  issuer: O=knative.dev; CN=control-plane
*  SSL certificate verify result: self signed certificate (18), continuing anyway.
```

