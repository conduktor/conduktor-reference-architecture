- need kubectl 1.33+
- helm repo update on `make install-conduktor-platform`


```
Error: execution error at (console/templates/console/ingress.yaml:58:14): Ingress TLS enabled require one of : 
- ingress.selfSigned 
- ingress.secrets with existing TLS secret or one to create 
- ingress.annotations for cert-manager
```

```
k get ingress -n conduktor 
NAME                CLASS   HOSTS                         ADDRESS        PORTS     AGE
conduktor-console   nginx   console.conduktor.localhost   192.168.97.2   80, 443   13m
conduktor-gateway   nginx   gateway.conduktor.localhost   192.168.97.2   80, 443   39m
```

```
curl -k -u admin:conduktor https://192.168.97.2/health
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

Same 404 not found with console in browser