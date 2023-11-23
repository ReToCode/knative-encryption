# Trust sources

## Options
- [trust-manager](https://cert-manager.io/docs/trust/trust-manager/)
- [k8s cluster-trust-bundles](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#cluster-trust-bundles)
- [OpenShift custom PKI](https://docs.openshift.com/container-platform/4.14/networking/configuring-a-custom-pki.html)
- [OpenShift Service Signer](https://docs.openshift.com/container-platform/4.14/security/certificates/service-serving-certificate.html)


## How workload trust is managed

There are different options, depending on the level, language/framework and requirements for reloading. In general, we have:

* Mounting the bundle to the filesystem
* Reading it from environment variable
* Accessing it from a secret/configmap via K8s api

Important is to decide if a reload without downtime is necessary, if so the workload must either watch changes on the K8s resource or watch the filesystem.
For the latter it is important, that `ionotify` on changing Secrets/ConfigMaps does not work super reliable on K8s. Tests showed that it is more reliable to regularly poll and check the certificate on the filesystem for changes.

Here are a few examples for golang:

* Saving the bundle as a file to a defined path: https://go.dev/src/crypto/x509/root_linux.go (note does not reload without restart)
* Reloading dynamically via K8s API: https://github.com/knative/serving/blob/main/pkg/activator/certificate/cache.go#L95
* Reloading from filesystem with a watcher process: https://github.com/knative/serving/blob/main/pkg/queue/certificate/watcher.go#L32


## Possible origins of CA bundles

### trust-manager

```bash
# Installation
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace
helm upgrade -i -n cert-manager trust-manager jetstack/trust-manager --wait

kubectl create ns demo
kubectl create -f yaml/trust-manager-labeled-cm.yaml
kubectl apply -f yaml/trust-manager-bundle.yaml
kubectl label ns demo knative-bundle=enabled
```

This updates the existing configmap in `demo`:

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
    knative-bundle: "true"
    trust.cert-manager.io/hash: ff5a4e77438c9cb389024a134169083f24468899229173f3fa1a3403f1c15acb
  labels:
    knative-bundle: "true"
    trust.cert-manager.io/bundle: knative-bundle
  name: knative-bundle
  namespace: demo
  ownerReferences:
    - apiVersion: trust.cert-manager.io/v1alpha1
      blockOwnerDeletion: true
      controller: true
      kind: Bundle
      name: knative-bundle
      uid: 82562ddb-fd38-486a-9003-4833141a836c
```

### k8s cluster-trust-bundles

This is only alpha in K8s 1.27, so not an option for us for now.


### OpenShift custom PKI

```bash
kubectl apply -f yaml/custom-pki-labeled-cm.yaml
```

This results in (shortened - as it's quite long):

```yaml
apiVersion: v1
data:
  ca-bundle.crt: |
    # List of CA in form:
    -----BEGIN CERTIFICATE-----
    
    -----END CERTIFICATE-----
kind: ConfigMap
metadata:
  annotations:
    knative-bundle: "true"
  labels:
    config.openshift.io/inject-trusted-cabundle: "true"
    knative-bundle: "true"
  name: custom-pki-cm
  namespace: demo
```

### OpenShift Service Signer

```bash
kubectl apply -f yaml/service-signer-annotated-cm.yaml
```

Results in:

```yaml
apiVersion: v1
data:
  service-ca.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDUTCCAjmgAwIBAgIIRiy/M3fY128wDQYJKoZIhvcNAQELBQAwNjE0MDIGA1UE
    Awwrb3BlbnNoaWZ0LXNlcnZpY2Utc2VydmluZy1zaWduZXJAMTcwMDc0MjQ0MjAe
    Fw0yMzExMjMxMjI3MjFaFw0yNjAxMjExMjI3MjJaMDYxNDAyBgNVBAMMK29wZW5z
    aGlmdC1zZXJ2aWNlLXNlcnZpbmctc2lnbmVyQDE3MDA3NDI0NDIwggEiMA0GCSqG
    SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDTG/HUArck12V5y9aEZVsYlufhOBGkL7Cp
    hajUP3ZtZgjY3DHxymJTIUnmuC72PJt+h0eENWQTHz9WKX8hLmGVv9Loue0FYNKq
    ITKsST/XbEHJ/OGO6ob3XknmvToF9fZSQLSXGTUYaWqCkUVLogvJAAEUzyrHrhso
    wUrdKDjPzKYltiIF/4GBnq044OL/qJhpfZ4+rjFiNtnRt9GTukKMmH1Q1ysFLLAY
    CCglc9dytoZ//67acYO4sW7iGaI69+NymptBuozp8nEJxBhyXTwwXSs9ytJkGamQ
    NdDDcL2LGFTBk7a3RsZwcrxwolJMz5dwh5Teb68a0TMvOPvXAHmbAgMBAAGjYzBh
    MA4GA1UdDwEB/wQEAwICpDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTbfpU/
    8xr5PIUOnTl/LWt0RMrscjAfBgNVHSMEGDAWgBTbfpU/8xr5PIUOnTl/LWt0RMrs
    cjANBgkqhkiG9w0BAQsFAAOCAQEAMpBVdhcu4G/aQUozdNrNwGmsoJcfz8//hY/7
    fSlg+HV1HFDmc6jEGtSUivfCTj3stSxTdh66ini2xz5DZoaL6vfMcgMaxA7zkMZP
    DUmyGXDyEoYVfpHHkgg5xaK5wo5QOE0RB/cbmzgGpIfTnN0hwRil6PCi+RwXR/T6
    Aw2fgPu0UZ6vsD3Lb8Hb7XdRqL9ouJmSJAiiBeFn0Ne23xm78AiFq/SsnX6Q0A3S
    6cOX7nSBzl+Ezq/KK2GlKaO/DZ+MEDZ2gNHI3tb6b68zQzOKunUJBKUKfiMb0Bsf
    P5ttpB0slWu9OAXoT3UHitoWGNqih46tqVkYWddacsyoJ8rrHw==
    -----END CERTIFICATE-----
kind: ConfigMap
metadata:
  annotations:
    knative-bundle: "true"
    service.beta.openshift.io/inject-cabundle: "true"
  labels:
    knative-bundle: "true"
  name: service-signer-ca
  namespace: demo
```

