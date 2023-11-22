# Serverless encryption
This repository contains stuff to hack around Serverless encryption.

## Visualization
![Visualization](https://raw.githubusercontent.com/ReToCode/diagrams/main/knative-encryption/encryption-overview.drawio.svg)

## Prerequisites
* A `kubernetes` cluster with `kubectl` configured that can provide services with type `LoadBalancer`

## Contents
* [helpers](./0-helpers)
* [initial research](./1-initial-research)
* [poc istio](./2-poc-net-istio)
* [poc kourier](./3-poc-kourier)
* [qp rotation](./4-qp-rotation)
* [system-internal-tls](./5-final-system-internal-tls)
* [cluster-local-domain-tls](./6-final-cluster-local-domain-tls)
* [full setup with cert-manager](./7-cert-manager-only)
