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
* [vision](./5-final)
