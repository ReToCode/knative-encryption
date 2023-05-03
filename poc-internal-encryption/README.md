# PoC: Setup with net-certmanager to generate cluster.local services

## Setup

```bash
kubectl apply -f https://github.com/knative/net-certmanager/releases/download/knative-v1.10.0/release.yaml
kubectl apply -f ./cert-manager-config
```

## Create a test-certificate

```bash
kubectl apply -f ./certificate
```

## Enable internal-encryption

```bash
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"internal-encryption":"true"}}'

# Force restart activator pods to open https listener
kubectl delete pod -n knative-serving -l app=activator
kubectl wait --timeout=60s --for=condition=Available deployment -n knative-serving activator
```

## Test a service with HTTP

Outside the cluster
```bash
curl http://hello-example.default.10.89.0.200.sslip.io
Hello World!
```

Inside the cluster
```bash
kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl hello-example.default
Hello World!

kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl hello-example.default.svc
Hello World!

kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl hello-example.default.svc.cluster.local
Hello World!
```

## Test a service with HTTPs

Outside the cluster

    This is not available, as it is auto-tls

Inside the cluster
```bash
kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl -k https://hello-example.default
Hello World!

kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl -k https://hello-example.default.svc
Hello World!

kubectl run curl --rm -n default --image=curlimages/curl --restart=Never -it -- curl -k https://hello-example.default.svc.cluster.local
Hello World!
```

## Check the certificate

Inside the cluster
```bash
kubectl run openssl --rm -n default --image=alpine/openssl --restart=Never -it --command -- sh -c "echo | openssl s_client -connect hello-example.default.svc.cluster.local:443 | openssl x509 -text"

Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            f6:ba:07:9e:83:bf:54:70:24:87:39:6d:c8:2b:1c:85
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = knative.dev
        Validity
            Not Before: May  3 06:45:41 2023 GMT
            Not After : Aug  1 06:45:41 2023 GMT
        Subject: CN = hello-example.default
        X509v3 Subject Alternative Name:
            DNS:hello-example.default, DNS:hello-example.default.svc, DNS:hello-example.default.svc.cluster.local
```
