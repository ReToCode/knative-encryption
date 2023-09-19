#!/usr/bin/env bash

echo "knative-serving: routing-serving-certs"
kubectl get secrets -n knative-serving routing-serving-certs -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -e DNS

echo "knative-serving: knative-serving-certs (legacy)"
kubectl get secrets -n knative-serving knative-serving-certs -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -e DNS

echo "default: serving-certs"
kubectl get secrets -n default serving-certs -o jsonpath={'.data.tls\.crt'} | base64 -d | openssl x509 -text | grep -e DNS

