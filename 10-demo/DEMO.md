# Knative Serving Encryption Demo

## Architecture

![Visualization](https://raw.githubusercontent.com/ReToCode/diagrams/main/knative-encryption/encryption-overview.drawio.svg)

## Initial situation Knative Service

```bash
kubectl get ksvc -A
```
```bash
kubectl get king helloworld -n first -o yaml | kubectl neat | bat -l yaml -P
```

## Integration with cert-manager

```bash
kubectl get clusterissuer
```
```bash
kubectl get cm config-certmanager -n knative-serving -o yaml | kubectl neat | bat -l yaml -P
```

## Use-Case 1: external-domain-tls

* We need certificates for each public domain (e.g. `helloworld.first.172.17.0.100.sslip.io`)
* The ClusterIssuer in `issuerRef` is used

#### Enable the feature

```bash
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"external-domain-tls":"enabled"}}'
```

#### What happens now?
* Knative Controller creates a `KnativeCertificate`
* net-certmanager creates cert-manager `Certificate` resources with the correct issuer
* Secrets contain certificates for external domain signed by TEST-ROOT-1

```bash
kubectl get kcert -n first
```
```bash
kubectl get cert -n first -o wide
```
```bash
kubectl get $(kubectl get secrets -n first -o name | head -1) -n first -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -E 'Subject:|Issuer'
```
```bash
kubectl get king helloworld -n first -o yaml | kubectl neat | bat -l yaml -P
```

#### Verifying

We can now call the Knative Service with https using TEST-ROOT-1 CA to verify trust

```bash
curl -si --cacert certs/root-1.crt https://helloworld.first.172.17.0.100.sslip.io
```

## Use-Case 2: cluster-local-domain-tls

* We need certificates for each cluster-local domain (e.g. `helloworld.first.svc.cluster.local`, `helloworld.first.svc`, `helloworld.first`)
* The ClusterIssuer in `clusterLocalIssuerRef` is used

#### Enable the feature

```bash
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"cluster-local-domain-tls":"enabled"}}'
```

#### What happens now?
* Knative Controller creates an additional `KnativeCertificate` with local domains 
* net-certmanager creates cert-manager `Certificate` resources with the correct issuer
* Secrets contain certificates for all local domains signed by TEST-ROOT-1

```bash
kubectl get kcert -A | grep local
```
```bash
kubectl get $(kubectl get secrets -n first -o name | grep local | head -1) -n first -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -E 'Subject:|Issuer|DNS'
```
```bash
kubectl get king helloworld -n first -o yaml | kubectl neat | bat -l yaml -P
```

#### Verifying

We can now call the Knative Service with https using TEST-ROOT-1 CA to verify trust (inside the cluster)

```bash
kubectl exec deployment/curl -n first -it -- curl -si https://helloworld.first --cacert /tmp/root-1.crt
```
```bash
kubectl exec deployment/curl -n first -it -- curl -si https://helloworld.first.svc --cacert /tmp/root-1.crt
```
```bash
kubectl exec deployment/curl -n first -it -- curl -si https://helloworld.first.svc.cluster.local --cacert /tmp/root-1.crt
```
```bash
kubectl run openssl --rm -n first --image=alpine/openssl --restart=Never -it --command -- sh -c "echo | openssl s_client -connect helloworld.first.svc.cluster.local:443 | openssl x509 -text | grep -E 'Subject:|Issuer|DNS'"
```

## Use-Case 3: system-internal-tls

* We need certificates for Knative internal components (Ingress-Gateway, Activator, Queue-Proxy)
* The ClusterIssuer in `systemInternalIssuerRef` is used

#### Enable the feature

```bash
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"system-internal-tls":"enabled"}}'
# restart activator
kubectl delete pod -n knative-serving -l app=activator --grace-period=0 --force
```

#### What happens now?
* cert-manager will create certificates for Activator and for each namespace where a `KnativeService` is present
* Ingress-Gateway and Activator will be configured to trust certificates signed by TEST-ROOT-1
* Queue-Proxy configuration will be updated to use the namespace secret
* All data-path communication will be encrypted using TLS

```bash
kubectl get kcert -n knative-serving
```
```bash
kubectl get cert -n knative-serving -o wide
```
```bash
kubectl get cert -n first -o wide
```
```bash
kubectl get $(kubectl get pod -n first -o name | grep helloworld | head -1) -n first -o yaml | kubectl neat | bat -l yaml -P
```
```bash
kubectl logs $(kubectl get pod -n first -o name | grep helloworld | head -1) -n first -c queue-proxy | grep -E 'certDir|Certificate|tls'
```
```bash
kubectl get king helloworld -n first -o yaml | kubectl neat | bat -l yaml -P
```

## CA Rotation

⚠️ Note: we only take care of trust in Knative system components, all other clients (like `curl` in this demo) need to also trust the CAs.

#### Description
* Currently, all certificates are signed by TEST-ROOT-1 CA
* We can update the CA Secret for cert-manager, it will then be used to sign new certificates (or existing ones if expired)
* To avoid downtime/issues, all clients (including Knative components) need to trust the `OLD` and the `NEW` CA until rotation is finished
* To achieve this, all CAs can be provided as one (or multiple) `ConfigMap` containing a PEM formatted list of CAs

#### Rotation demo

Set cert-manager CA to TEST-ROOT-2
```bash
kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-2.key \
    --cert=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -
```

Certificates (per default) are valid for 2160h, so we force a renewal of the certificates in the `first` namespace

```bash
kubectl delete secret -n first --all
kubectl delete certificate -n first --all
```

Verify that the certificate is now signed by TEST-ROOT-2

```bash
kubectl get $(kubectl get secrets -n first -o name | grep local | head -1) -n first -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -E 'Subject:|Issuer|DNS'
```

Call the Knative Service from via external domain (⚠️ Note: we now need to trust root-2.crt in curl)

```bash
curl -i --cacert certs/root-2.crt https://helloworld.first.172.17.0.100.sslip.io
```

Try with the second service (which has still certificates signed by TEST-ROOT-1)

```bash
curl -i --cacert certs/root-1.crt https://helloworld.second.172.17.0.100.sslip.io
```

We can add both CAs to the trust store of Knative components with a ConfigMap

```bash
kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/root-1.crt --from-file=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -
kubectl label cm/my-trust-bundle -n knative-serving knative-ca-trust-bundle="true"
```

Verify again
```bash
curl -i --cacert certs/root-2.crt https://helloworld.first.172.17.0.100.sslip.io
```
```bash
curl -i --cacert certs/root-1.crt https://helloworld.second.172.17.0.100.sslip.io
```

To fully rotate, we need to force recreate certificates in `second` and `knative-serving` namespace as well

```bash
# second
kubectl delete secret -n second --all
kubectl delete certificate -n second --all

# knative-serving
kubectl delete secret -n knative-serving routing-serving-certs
kubectl delete certificate -n knative-serving routing-serving-certs
```

Drop TEST-ROOT-1 from the trust-bundle

```bash
kubectl create configmap -n knative-serving my-trust-bundle --from-file=certs/root-2.crt --dry-run=client -o yaml | kubectl apply -f -
```

Final verification

```bash
curl -i --cacert certs/root-2.crt https://helloworld.first.172.17.0.100.sslip.io
```
```bash
curl -i --cacert certs/root-2.crt https://helloworld.second.172.17.0.100.sslip.io
```
