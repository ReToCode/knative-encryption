#!/usr/bin/env bash

kubectl patch cm config-network -n "knative-serving" -p '{"data":{"cluster-local-domain-tls":"disabled"}}'
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"external-domain-tls":"disabled"}}'
kubectl patch cm config-network -n "knative-serving" -p '{"data":{"system-internal-tls":"disabled"}}'

kubectl create -n cert-manager secret tls test-ca-secret \
    --key=certs/root-1.key \
    --cert=certs/root-1.crt --dry-run=client -o yaml | kubectl apply -f -

kubectl delete kcert -n first --all
kubectl delete kcert -n second --all
kubectl delete cert --all -A
kubectl delete secret -n first --all
kubectl delete secret -n second --all
kubectl delete secret routing-serving-certs -n knative-serving

kubectl delete cm -n knative-serving my-trust-bundle

kubectl delete pod -n knative-serving -l app=activator --grace-period=0 --force
kubectl delete pod -n knative-serving -l app=net-kourier-controller --grace-period=0 --force
kubectl delete pod -n kourier-system --all --grace-period=0 --force
