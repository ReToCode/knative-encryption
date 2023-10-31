# Knative cluster-local-domain-tls with Knative Issuer

## Setup

```bash
# Install serving (in serving directory)
git checkout cluster-local-tls-internal-issuer
ko apply --selector knative.dev/crd-install=true -Rf config/core/
kubectl wait --for=condition=Established --all crd
ko apply -Rf config/core/

# Install kourier (in kourier directory)
git checkout cluster-local-tls
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
  
# Enable cluster-local-domain-tls encryption
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"cluster-local-domain-tls":"enabled"}}'

# Use knative internal issuer
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"certificate-class":"knative-selfsigned.certificate.networking.knative.dev"}}'
```

Optional: enable request logging
```bash
# Activator and Q-P
kubectl patch configmap/config-observability \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"logging.enable-request-log":"true"}}'
  
# Kourier gateway
kubectl patch configmap/config-kourier \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"logging.enable-request-log":"true"}}'
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
kubectl get secrets serving-certs-cluster-local-domain-ca -n knative-serving -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text > ca.crt
kubectl cp ca.crt "default/$(kubectl get -n default pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
kubectl cp ca.crt "second/$(kubectl get -n second pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
rm ca.crt
```


### Verify with SNI

Just for manual testing:

```bash
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default --cacert /tmp/ca.crt
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default.svc --cacert /tmp/ca.crt
kubectl exec deployment/curl -n default -it -- curl -si https://helloworld.default.svc.cluster.local --cacert /tmp/ca.crt
kubectl run openssl --rm -n default --image=alpine/openssl --restart=Never -it --command -- sh -c "echo | openssl s_client -connect helloworld.default.svc.cluster.local:443 | openssl x509 -text"
```

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

### Verify with one global cert in kourier

Preparation

```bash
# Generate CA and certificates
export san="knative-kourier"

openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
-subj '/O=Example/CN=Example' \
-keyout ca.key \
-out ca.crt

openssl req -out tls.csr -newkey rsa:2048 -nodes -keyout tls.key \
-subj "/CN=Example/O=Example" \
-addext "subjectAltName = DNS:$san"

openssl x509 -req -extfile <(printf "subjectAltName=DNS:$san") \
-days 365 -in tls.csr \
-CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt

kubectl create -n knative-serving secret tls server-certs \
--key=tls.key \
--cert=tls.crt --dry-run=client -o yaml | oc apply -f -

# Enable one cert in kourier config
kubectl -n "knative-serving" patch configmap/config-kourier \
  --type merge \
  -p '{"data":{"cluster-cert-secret":"server-certs"}}'

# Copy the CA in the curl pods
kubectl cp ca.crt "default/$(kubectl get -n default pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/kourier-ca.crt
kubectl cp ca.crt "second/$(kubectl get -n second pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/kourier-ca.crt

# Cleanup
rm ca.crt ca.key ca.srl tls.crt tls.csr tls.key

# Restart net-kourier pod
kubectl delete pod -n knative-serving -l app=net-kourier-controller
kubectl delete pod -n kourier-system -l app=3scale-kourier-gateway
```

📝 Note: Only one CN without SANs is returned, it is the same, no matter which url you call the Knative Service with!

```text
*   Trying 10.96.193.114:443...
* Connected to helloworld.default (10.96.193.114) port 443 (#0)
* ALPN: offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=Example; O=Example
*  start date: May 24 09:28:40 2023 GMT
*  expire date: May 23 09:28:40 2024 GMT
*  issuer: O=Example; CN=Example
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* using HTTP/2
* h2 [:method: GET]
* h2 [:scheme: https]
* h2 [:authority: helloworld.default]
* h2 [:path: /]
* h2 [user-agent: curl/8.1.1-DEV]
* h2 [accept: */*]
* Using Stream ID: 1 (easy handle 0xffff99860aa0)
> GET / HTTP/2
> Host: helloworld.default
> User-Agent: curl/8.1.1-DEV
> Accept: */*
> 
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
< HTTP/2 200 
HTTP/2 200 
< content-length: 20
content-length: 20
< content-type: text/plain; charset=utf-8
content-type: text/plain; charset=utf-8
< date: Wed, 24 May 2023 11:10:35 GMT
date: Wed, 24 May 2023 11:10:35 GMT
< x-envoy-upstream-service-time: 1935
x-envoy-upstream-service-time: 1935
< server: envoy
server: envoy

< 
Hello Go Sample v1!
```

⛔️ Note: The certificate is not trusted by curl, as a client would need to manually match the SAN (which curl cannot do)! [More info](https://access.redhat.com/documentation/en-us/red_hat_openshift_serverless/1.28/html/serving/external-and-ingress-routing#serverless-enabling-tls-local-services_cluster-local-availability).

```bash
kubectl exec deployment/curl -n default -it -- curl -siv https://helloworld.default.svc.cluster.local --cacert /tmp/kourier-ca.crt
```

```text
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=Example; O=Example
*  start date: May 24 09:28:40 2023 GMT
*  expire date: May 23 09:28:40 2024 GMT
*  subjectAltName does not match helloworld.default.svc.cluster.local
* SSL: no alternative certificate subject name matches target host name 'helloworld.default.svc.cluster.local'
```

