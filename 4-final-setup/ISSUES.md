# Issues

## Kourier
Related discussion: https://cloud-native.slack.com/archives/C04LMU0AX60/p1684344582028059?thread_ts=1684321868.604549&cid=C04LMU0AX60

Calling a service with just the k8s service name does not work:

```bash
kubectl exec deployment/curl -n default -it -- curl -siv http://helloworld        

*   Trying 10.96.193.114:80...
* Connected to helloworld (10.96.193.114) port 80 (#0)
> GET / HTTP/1.1
> Host: helloworld
> User-Agent: curl/8.1.1-DEV
> Accept: */*
> 
< HTTP/1.1 404 Not Found
HTTP/1.1 404 Not Found
< date: Wed, 24 May 2023 08:04:07 GMT
date: Wed, 24 May 2023 08:04:07 GMT
< server: envoy
server: envoy
< content-length: 0
content-length: 0
```
