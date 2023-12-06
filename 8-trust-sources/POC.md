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
