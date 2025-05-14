## installation issues

- need kubectl 1.33+
- helm repo update on `make install-conduktor-platform`

## console tls issues
```
Error: execution error at (console/templates/console/ingress.yaml:58:14): Ingress TLS enabled require one of : 
- ingress.selfSigned 
- ingress.secrets with existing TLS secret or one to create 
- ingress.annotations for cert-manager
```

## terraform issues

```
make init-conduktor-platform
```

│ Error: Client Error
│ 
│   with conduktor_console_group_v2.admin,
│   on main.tf line 29, in resource "conduktor_console_group_v2" "admin":
│   29: resource "conduktor_console_group_v2" "admin" {
│ 
│ Unable to create group, got error: Invalid token.

## Kafka issues

- k3d doesn't map 9092
- ingress doesn't have routing rule for 9092
- gateway advertised host is incorrect if you want to serve traffic from outside of kubernetes