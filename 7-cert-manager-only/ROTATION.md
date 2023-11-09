# Rotation with net-certmanager

## Prerequisites
* Install setup according to [README.md](./README.md)
* Enable all encryption flags
* Restart activator
* Deploy the KSVC and run the verify.sh script


## Preparation

```bash
# First, remove the selfsigned issuer and certificates
kubectl delete certificate knative-selfsigned-ca -n cert-manager

# Create two root CAs
mkdir certs
openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -subj '/O=ROOT-A/CN=example.com' -keyout certs/root-a-key.pem -out certs/root-a.pem
openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -subj '/O=ROOT-B/CN=example.com' -keyout certs/root-b-key.pem -out certs/root-b.pem

# We start out with only root-a being used by cert-manager
kubectl create secret tls knative-selfsigned-ca -n cert-manager --key=certs/root-a-key.pem --cert=certs/root-a.pem
kubectl get secrets knative-selfsigned-ca -n cert-manager -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -i issuer
        Issuer: O = ROOT-A, CN = example.com
```

### Helper functions
```bash
force_rotation() {
    # with root-a configured, we need to force a renewal to make sure we start out with root-a as issuer
    # note: cert-duration is 2160h, so this will force a renewal
    kubectl patch certificate routing-serving-certs -n knative-serving --patch '
    - op: replace
      path: /spec/renewBefore
      value: 2159h59m55s
    ' --type=json
    sleep 5
    kubectl patch certificate routing-serving-certs -n knative-serving --patch '
    - op: remove
      path: /spec/renewBefore
    ' --type=json

    # serving-certs is owned by Knative, so we cannot patch it, but we can delete it
    kubectl delete certificate serving-certs -n default
}
```

## 1) for system-internal-tls

### Using root-a only

```bash
# certificates that need rotation are
# knative-serving/routing-serving-certs (activator cert)
# all namespaces/serving-certs (queue-proxy certs)

# force a rotation
force_rotation

# verify that the new issuer was used for all certificates
kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -i issuer
        Issuer: O = ROOT-A, CN = example.com
kubectl get secrets serving-certs -n default -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -i issuer
        Issuer: O = ROOT-A, CN = example.com

# check what ca.crt is included in the generated certificates
kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.ca\.crt'} | base64 -d | openssl x509 -text | grep -i subject:
        Subject: O = ROOT-A, CN = example.com

# Verify that everything still works as expected
kubectl get secrets knative-selfsigned-ca -n cert-manager -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text > ca.crt
kubectl cp ca.crt "default/$(kubectl get -n default pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
kubectl cp ca.crt "second/$(kubectl get -n second pod -o=name | grep curl | sed 's/^.\{4\}//')":/tmp/
rm ca.crt
kubectl exec deployment/curl -n default -it -- curl https://helloworld.default --cacert /tmp/ca.crt
curl -k https://helloworld.default.192.168.105.100.sslip.io
```

### Adding root-a and root-b as trusted CA
```bash
# create a file containing root-a first, then root-b as per https://cert-manager.io/docs/configuration/ca/. 
# The last certificate will be treated as the "root" and will be put in the ca.crt field of all certificates
cat certs/root-a.pem certs/root-b.pem > certs/root-a-then-b.pem
kubectl delete secret knative-selfsigned-ca -n cert-manager
kubectl create secret tls knative-selfsigned-ca -n cert-manager --key=certs/root-a-key.pem --cert=certs/root-a-then-b.pem

# verify both certs are in there
kubectl get secrets knative-selfsigned-ca -n cert-manager -o jsonpath={'.data.tls\.crt'} | base64 -d

# force a rotation
force_rotation

# verify that the new issuer was used for all certificates
kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -i issuer
        Issuer: O = ROOT-A, CN = example.com
kubectl get secrets serving-certs -n default -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -i issuer
        Issuer: O = ROOT-A, CN = example.com

# check what ca.crt is included in the generated certificates
kubectl get secrets routing-serving-certs -n knative-serving -o jsonpath={'.data.ca\.crt'} | base64 -d | openssl x509 -text | grep -i subject:
        Subject: O = ROOT-A, CN = example.com
```

### Resigning all certificates from root-b


### Removing root-a from the trust pool




