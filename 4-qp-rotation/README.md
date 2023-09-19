# Queue Proxy cert rotation support

## Setup

```bash
# Enable internal encryption
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"internal-encryption":"true"}}'

# Restart activator (for now needed)
kubectl delete pod -n knative-serving -l --grace-period=0 app=activator
```

## Deploy a Knative Service
```bash
# KSVC does not scale to zero to see if certs are reloaded correctly
kubectl apply -f ./ksvc.yaml

kubectl apply -f ../0-helpers/curl.yaml
```

## Testing
```bash
POD_IP=$(kubectl get -n default $(kubectl get po -n default -o name -l app=helloworld-00001) --template '{{.status.podIP}}')

# Check certificate before
oc exec deployment/curl -n default -it -- curl -vik --http1.1 https://$POD_IP:8112

* Server certificate:
*  subject: O=knative.dev; CN=control-protocol-certificate
*  start date: Jul 31 13:25:22 2023 GMT
*  expire date: Aug 30 13:25:22 2023 GMT
*  issuer: O=knative.dev

# Rotate the certificate
# Drop all keys of secret `serving-certs-ctrl-ca`

# Wait a bit
sleep 90

# Check certificate again
oc exec deployment/curl -n default -it -- curl -vik --http1.1 https://$POD_IP:8112

* Server certificate:
*  subject: O=knative.dev; CN=control-protocol-certificate
*  start date: Jul 31 13:56:29 2023 GMT
*  expire date: Aug 30 13:56:29 2023 GMT ## this is using the new cert now
*  issuer: O=knative.dev
```

```text
user-container 2023/07/31 13:54:03 helloworld: starting server...
user-container 2023/07/31 13:54:03 helloworld: listening on port 8080
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.888910533Z","caller":"logging/config.go:80","message":"Unable to read vcs.revision from binary"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889395451Z","logger":"queueproxy","caller":"certificate/watcher.go:49","message":"Starting to watch the following directories for changes{certDir 15 0 /var/lib/knative/certs <nil>} {keyDir 15 0 /var/lib/knative/certs <nil>}","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889669452Z","logger":"queueproxy","caller":"certificate/watcher.go:116","message":"Certificate and/or key have changed on disk and were reloaded.","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889690869Z","logger":"queueproxy","caller":"sharedmain/main.go:267","message":"Starting queue-proxy","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889704577Z","logger":"queueproxy","caller":"sharedmain/main.go:281","message":"Starting tls server admin:8022","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889738994Z","logger":"queueproxy","caller":"sharedmain/main.go:273","message":"Starting http server metrics:9090","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889758202Z","logger":"queueproxy","caller":"sharedmain/main.go:273","message":"Starting http server main:8012","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:54:07.889773828Z","logger":"queueproxy","caller":"sharedmain/main.go:281","message":"Starting tls server main:8112","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
user-container 2023/07/31 13:54:40 helloworld: received a request
queue-proxy {"severity":"INFO","timestamp":"2023-07-31T13:57:07.890255096Z","logger":"queueproxy","caller":"certificate/watcher.go:116","message":"Certificate and/or key have changed on disk and were reloaded.","knative.dev/key":"default/helloworld-00001","knative.dev/pod":"helloworld-00001-deployment-7cf747576d-ctl8p"}
user-container 2023/07/31 13:57:54 helloworld: received a request
```