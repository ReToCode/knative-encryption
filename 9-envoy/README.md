# Envoy



```bash
# Run nginx
nginx -g "daemon off;" -c  /Users/rlehmann/code/retocode/knative-encryption/9-envoy/nginx-tls.config

# Run envoy
envoy -c /Users/rlehmann/code/retocode/knative-encryption/9-envoy/envoy-upstream-tls.yaml
```
