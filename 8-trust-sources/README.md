# Trust sources

## Options
- [trust-manager](https://cert-manager.io/docs/trust/trust-manager/)
- [k8s cluster-trust-bundles](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#cluster-trust-bundles)
- [OpenShift custom PKI](https://docs.openshift.com/container-platform/4.14/networking/configuring-a-custom-pki.html)
- [OpenShift Service Signer](https://docs.openshift.com/container-platform/4.14/security/certificates/service-serving-certificate.html)

## How workload trust is achieved

### trust-manager

```bash
# Installation
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace
helm upgrade -i -n cert-manager trust-manager jetstack/trust-manager --wait

kubectl create ns demo
kubectl apply -f yaml/trust-manager-bundle.yaml
kubectl label ns demo knative-bundle=enabled
```

This creates a new config-map in `demo`:

```yaml
apiVersion: v1
data:
  cacerts.pem: |
    -----BEGIN CERTIFICATE-----
    MIIDDTCCAfWgAwIBAgIQMQuip05h7NLQq2TB+j9ZmTANBgkqhkiG9w0BAQsFADAW
    MRQwEgYDVQQDEwtrbmF0aXZlLmRldjAeFw0yMzExMjIwOTAwNDhaFw0yNDAyMjAw
    OTAwNDhaMBYxFDASBgNVBAMTC2tuYXRpdmUuZGV2MIIBIjANBgkqhkiG9w0BAQEF
    AAOCAQ8AMIIBCgKCAQEA3clC3CV7sy0TpUKNuTku6QmP9z8JUCbLCPCLACCUc1zG
    FEokqOva6TakgvAntXLkB3TEsbdCJlNm6qFbbko6DBfX6rEggqZs40x3/T+KH66u
    4PvMT3fzEtaMJDK/KQOBIvVHrKmPkvccUYK/qWY7rgBjVjjLVSJrCn4dKaEZ2JNr
    Fd0KNnaaW/dP9/FvviLqVJvHnTMHH5qyRRr1kUGTrc8njRKwpHcnUdauiDoWRKxo
    Zlyy+MhQfdbbyapX984WsDjCvrDXzkdGgbRNAf+erl6yUm6pHpQhyFFo/zndx6Uq
    QXA7jYvM2M3qCnXmaFowidoLDsDyhwoxD7WT8zur/QIDAQABo1cwVTAOBgNVHQ8B
    Af8EBAMCAgQwEwYDVR0lBAwwCgYIKwYBBQUHAwEwDwYDVR0TAQH/BAUwAwEB/zAd
    BgNVHQ4EFgQU7p4VuECNOcnrP9ulOjc4J37Q2VUwDQYJKoZIhvcNAQELBQADggEB
    AAv26Vnk+ptQrppouF7yHV8fZbfnehpm07HIZkmnXO2vAP+MZJDNrHjy8JAVzXjt
    +OlzqAL0cRQLsUptB0btoJuw23eq8RXgJo05OLOPQ2iGNbAATQh2kLwBWd/CMg+V
    KJ4EIEpF4dmwOohsNR6xa/JoArIYH0D7gh2CwjrdGZr/tq1eMSL+uZcuX5OiE44A
    2oXF9/jsqerOcH7QUMejSnB8N7X0LmUvH4jAesQgr7jo1JTOBs7GF6wb+U76NzFa
    8ms2iAWhoplQ+EHR52wffWb0k6trXspq4O6v/J+nq9Ky3vC36so+G1ZFkMhCdTVJ
    ZmrBsSMWeT2l07qeei2UFRU=
    -----END CERTIFICATE-----
kind: ConfigMap
metadata:
  annotations:
    trust.cert-manager.io/hash: ff5a4e77438c9cb389024a134169083f24468899229173f3fa1a3403f1c15acb
  labels:
    trust.cert-manager.io/bundle: knative-bundle
  name: knative-bundle
  namespace: demo
  ownerReferences:
  - apiVersion: trust.cert-manager.io/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: Bundle
    name: knative-bundle
    uid: fc27ebe2-be78-49ed-b522-bd358c198fbc

```
