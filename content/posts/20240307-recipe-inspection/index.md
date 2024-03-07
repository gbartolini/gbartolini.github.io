---
title: "CloudNativePG Recipe 2 - Inspecting Default Resources in a CloudNativePG Cluster"
date: 2024-03-08
description: "Exploring the default resources set up by CloudNativePG along with a PostgreSQL cluster"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "app", "microservice database", "streaming_replica", "configmaps", "secrets", "mTLS", "PKI", "certificates", "pgpass", "password", "security"]
cover: cover.png
thumb: thumb.png
draft: false
---

_Dive into the nitty-gritty of how CloudNativePG works its magic with
PostgreSQL cluster stuff, zooming in on configmaps and secrets. Peek behind the
curtain of the default Private Key Infrastructure – the secret sauce for
stress-free mutual TLS authentication. Get to know the default user and
database setups, all decked out for maximum security. This article is your
go-to roadmap, cruising through CloudNativePG's resource wizardry and dishing
out real-world tips for a breeze in deploying and handling PostgreSQL clusters._

<!--more-->

---

In my [previous recipe]({{< relref "../20240303-recipe-local-setup/index.md">}}),
I provided a step-by-step guide on setting up a local playground for
CloudNativePG.

In this second recipe, let's delve into a first group of resources that
CloudNativePG automatically configures alongside your requested PostgreSQL
cluster. These resources play a crucial role in supporting the implementation of the
[microservice database]({{< relref "../20240228-maximizing-microservice-databases-with-k8s-postgres-cloudnativepg/index.md">}})
paradigm.

I'll assume that you've installed the `cluster-example` PostgreSQL cluster on
your local `kind` Kubernetes cluster (as explained in
[Recipe #1]({{< relref "../20240303-recipe-local-setup/index.md">}})),
and you've also set up the `cnpg` plugin for `kubectl`.

## Default ConfigMaps

Let's start by examining the `ConfigMap` resources installed by CloudNativePG
for a PostgreSQL `Cluster`:

```sh
kubectl get configmaps
```

This command should produce a similar output:

```console
NAME                      DATA   AGE
cnpg-default-monitoring   1      14h
```

Focus on the `cnpg-default-monitoring` ConfigMap, which CloudNativePG installs by
default. This ConfigMap contains built-in metrics for the [embedded Prometheus
exporter](https://cloudnative-pg.io/documentation/current/monitoring/#user-defined-metrics).
Inspect its content using:

```sh
kubectl get -o yaml configmaps cnpg-default-monitoring | less
```

By default, CloudNativePG associates this ConfigMap in the cluster resource.
Verify this by running:

```sh
kubectl get cluster cluster-example \
  -o jsonpath="{.spec.monitoring}"  | jq -C
```

Pay attention to the `monitoring` section in the returned JSON object:

```json
{
  "customQueriesConfigMap": [
    {
      "key": "queries",
      "name": "cnpg-default-monitoring"
    }
  ],
  "disableDefaultQueries": false,
  "enablePodMonitor": false
}
```

For more details on the observability framework available in CloudNativePG,
including creating custom metrics, refer to the
["Monitoring"](https://cloudnative-pg.io/documentation/current/monitoring/)
section in the documentation.

## Default Secrets

Now, let's explore the core aspects – secrets. Run the following command:

```sh
kubectl get secrets
```

You should see:

```console
NAME                          TYPE                       DATA   AGE
cluster-example-app           kubernetes.io/basic-auth   9      14h
cluster-example-ca            Opaque                     2      14h
cluster-example-replication   kubernetes.io/tls          2      14h
cluster-example-server        kubernetes.io/tls          2      14h
````

Let's briefly discuss each:

- `cluster-example-app`: secret containing information about the `app` user in
  the PostgreSQL cluster, including credentials
- `cluster-example-ca`: secret containing the Certification Authority (CA) used
  by the operator for emitting TLS certificates
- `cluster-example-replication`: secret with the TLS client certificate for
  streaming replication in the HA cluster
- `cluster-example-server`: secret with the TLS certificate of the PostgreSQL
  server

### Understanding the `app` User Secret

The `cluster-example-app` secret, classified as `kubernetes.io/basic-auth`,
holds essential details about the `app` user within the PostgreSQL cluster.
This user acts as the owner of the `app` database, a topic we'll explore
further in this section. The information encapsulated in this secret covers the
username, password, Postgres password file, connection string, and more. As
common, each piece of information is encoded in `base64`, aligning with
standard secret resource practices.

To gain insights into the contents of the `cluster-example-app` secret, use
the following command:

```sh
kubectl describe secret cluster-example-app
```

For instance, let's inspect the password file prepared for the `app` user by
executing the following command:

```sh
kubectl get secret cluster-example-app \
  -o jsonpath="{.data.pgpass}" | base64 -d
```

In a disposable environment, this command might return something like:

```console
cluster-example-rw:5432:app:app:<password>
```

Understanding this output is crucial as it empowers us to mount this secret as
a project volume within a container and access the password file from inside
the container. By doing so, we can utilize the sensitive information securely
without exposing any passwords. This practice enhances security and is
particularly valuable in containerized environments.

Feel free to replicate the above process for any field within the secret,
including the `password`. Enjoy exploring and leveraging the power of securely
managing sensitive information in your projects!

### Secrets for Private Key Infrastructure (PKI) and Transport Layer Security (TLS)

One of the pillars of CloudNativePG is the secure-by-default posture, the
results of years of practicing of the
["shift-left on security" DevOps capability](https://dora.dev/devops-capabilities/process/shifting-left-on-security/).

CloudNativePG by default creates a CA for the cluster, and uses it to emit the
TLS certificate for each Postgres server in the HA cluster and implement mutual
TLS with client applications.

Let's inspect for example the CA certificate with in the `cluster-example-ca`
secret:

```sh
kubectl get secret cluster-example-ca \
  -o jsonpath="{.data['ca\.crt']}" | \
  base64 -d | \
  openssl x509 -text -noout
```

This will return:

```yaml
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            d2:a1:0f:48:4b:c4:33:38:72:f9:64:cf:d9:b0:56:e5
        Signature Algorithm: ecdsa-with-SHA256
        Issuer: OU=default, CN=cluster-example
        Validity
            Not Before: Mar  7 17:09:44 2024 GMT
            Not After : Jun  5 17:09:44 2024 GMT
        Subject: OU=default, CN=cluster-example
        Subject Public Key Info:
            Public Key Algorithm: id-ecPublicKey
                Public-Key: (256 bit)
                pub:
                    04:a0:5a:da:e4:3e:bb:c7:3a:39:4e:9c:02:a7:d2:
                    05:bd:68:07:06:f2:2f:94:d2:92:59:be:5f:15:9c:
                    24:06:a0:87:ff:1b:1d:b7:0d:ff:ad:ef:da:98:e3:
                    04:bb:e0:06:93:f8:64:5e:1d:d0:52:77:a5:68:7d:
                    f8:26:e8:c2:57
                ASN1 OID: prime256v1
                NIST CURVE: P-256
        X509v3 extensions:
            X509v3 Key Usage: critical
                Certificate Sign
            X509v3 Basic Constraints: critical
                CA:TRUE
            X509v3 Subject Key Identifier:
                33:0F:04:43:ED:4C:8D:B0:39:57:50:67:8F:04:C6:CE:57:31:9C:6A
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:45:02:20:1c:e4:8e:43:d4:02:74:df:09:1d:36:0d:18:b0:
        dc:26:2f:6d:75:2b:ae:01:42:e3:be:80:0e:b2:cf:01:09:5b:
        02:21:00:c5:31:75:85:26:98:9e:76:e7:ea:5f:ad:b8:02:b9:
        bf:8b:0c:2c:dc:01:7e:25:e7:15:d7:7c:01:5e:0d:c0:14
```

This CA certificate is used by CloudNativePG to sign the PostgreSQL server
certificate, stored in the `cluster-example-server` secret. Try:

```sh
kubectl get secret cluster-example-server \
  -o jsonpath="{.data['tls\.crt']}" | \
  base64 -d | \
  openssl x509 -text -noout
```

Look at the returned certificate, paying specific attention to the `Subject`
and `X509v3 Subject Alternative Name` sections:

```yaml
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            79:89:0e:55:f5:d8:ea:0e:62:85:b0:b5:b3:91:22:b6
        Signature Algorithm: ecdsa-with-SHA256
        Issuer: OU=default, CN=cluster-example
        Validity
            Not Before: Mar  7 17:09:44 2024 GMT
            Not After : Jun  5 17:09:44 2024 GMT
        Subject: CN=cluster-example-rw
        Subject Public Key Info:
            Public Key Algorithm: id-ecPublicKey
                Public-Key: (256 bit)
                pub:
                    04:5f:2f:3e:f7:dc:d3:f0:1b:06:e5:6e:a5:96:cb:
                    ba:74:06:69:d3:5f:17:d6:56:29:df:aa:54:da:e8:
                    6a:5a:45:a7:45:c8:78:92:8a:fb:f5:df:d2:4a:1c:
                    7b:b6:77:00:95:ff:8a:14:bd:6b:dc:a3:6b:69:00:
                    51:3e:9c:e1:c7
                ASN1 OID: prime256v1
                NIST CURVE: P-256
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment, Key Agreement
            X509v3 Extended Key Usage:
                TLS Web Server Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Authority Key Identifier:
                33:0F:04:43:ED:4C:8D:B0:39:57:50:67:8F:04:C6:CE:57:31:9C:6A
            X509v3 Subject Alternative Name:
                DNS:cluster-example-rw, DNS:cluster-example-rw.default, DNS:cluster-example-rw.default.svc, DNS:cluster-example-r, DNS:cluster-example-r.default, DNS:cluster-example-r.default.svc, DNS:cluster-example-ro, DNS:cluster-example-ro.default, DNS:cluster-example-ro.default.svc, DNS:cluster-example-rw
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:46:02:21:00:ee:69:23:35:23:af:2c:ca:da:6a:af:c7:90:
        60:40:35:70:d8:5b:3f:91:88:31:bc:17:65:35:db:b4:b8:52:
        c4:02:21:00:93:30:96:ce:4b:49:6b:ff:a0:83:cf:6b:91:2d:
        e0:5d:33:17:42:d6:3d:02:24:94:7f:fa:3d:e0:c2:04:0d:6b

```

The `X509v3 Subject Alternative Name` section contains all the alternative
names of any Kubernetes service automatically created for the cluster.

Besides the certificate, the above secrets also contain the private key,
enabling the operator to self-sign the client certificates, starting from the
one used for streaming replication.

### The TLS certificate for streaming replication

The last certificate is `cluster-example-replication`, containing the
certificate for the `streaming_replica` user in PostgreSQL. Run:

```sh
kubectl get secret cluster-example-replication \
  -o jsonpath="{.data['tls\.crt']}" | \
  base64 -d | \
  openssl x509 -text -noout
```

You can spot the Postgres user name from the `Subject` field below:

```yaml
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            f2:69:76:c2:74:41:0c:a6:ca:be:f9:99:eb:3e:9b:78
        Signature Algorithm: ecdsa-with-SHA256
        Issuer: OU=default, CN=cluster-example
        Validity
            Not Before: Mar  7 17:09:44 2024 GMT
            Not After : Jun  5 17:09:44 2024 GMT
        Subject: CN=streaming_replica
        Subject Public Key Info:
            Public Key Algorithm: id-ecPublicKey
                Public-Key: (256 bit)
                pub:
                    04:87:06:92:01:10:07:d3:2d:10:6b:6e:27:4b:1a:
                    c3:f5:b4:c2:25:a4:d6:77:f4:a2:d3:d2:22:47:fe:
                    68:60:1d:a6:19:7a:ed:e2:30:f1:d5:8d:c6:ca:67:
                    81:ca:20:50:48:63:7e:b3:e2:16:a1:79:4d:f5:36:
                    d0:2c:c4:f2:d5
                ASN1 OID: prime256v1
                NIST CURVE: P-256
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Agreement
            X509v3 Extended Key Usage:
                TLS Web Client Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Authority Key Identifier:
                33:0F:04:43:ED:4C:8D:B0:39:57:50:67:8F:04:C6:CE:57:31:9C:6A
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:71:7e:62:67:62:c2:82:ea:c7:9b:49:2e:59:90:
        a3:8b:8a:a9:a2:51:6c:fd:18:ff:99:0e:fb:1e:81:12:df:6b:
        02:20:35:ea:a0:ff:8c:a7:15:b4:79:a3:51:9f:b0:28:ce:40:
        b0:42:3c:3c:81:65:7d:16:3e:16:a9:0a:8d:b6:d2:c8
```

The feature we've incorporated into CloudNativePG as the **default behavior**
is somewhat uncommon with PostgreSQL outside the Kubernetes ecosystem. This
rarity is attributed to the inherent complexity of managing certificates, a
challenge mitigated by Kubernetes, where certificates serve as a foundational
element. Moreover, by default, CloudNativePG systematically rotates these
certificates every 90 days.

For those familiar with PostgreSQL, the instantaneous configuration of the
`primary_conninfo` setting for mutual TLS authentication (sans password) on the
initial replica in the cluster is a noteworthy occurrence. Verify this behavior
firsthand by executing the following command:

```sh
kubectl exec -ti -c postgres cluster-example-2 \
  -- psql -qAt -c 'SHOW primary_conninfo'
```

This will produce output similar to the following:

```
host=cluster-example-rw
user=streaming_replica
port=5432
sslkey=/controller/certificates/streaming_replica.key
sslcert=/controller/certificates/streaming_replica.crt
sslrootcert=/controller/certificates/server-ca.crt
application_name=cluster-example-2
sslmode=verify-ca
```

If the security provided by self-signed certificates isn't sufficient for your
needs, you have the flexibility to integrate CloudNativePG with external
certificate solutions such as [cert-manager](https://cert-manager.io/), thereby
enhancing security and encryption in your PostgreSQL deployments.

## Default global objects in PostgreSQL

By default, CloudNativePG establishes the following:

- The `streaming_replica` user, as previously discussed
- An application user named `app`
- An application database named `app`

To inspect the users, execute the following command:

```sh
kubectl exec -ti -c postgres cluster-example-1 -- psql -c '\du'
```

This command produces the following output:

```console
                                 List of roles
     Role name     |                         Attributes
-------------------+------------------------------------------------------------
 app               |
 postgres          | Superuser, Create role, Create DB, Replication, Bypass RLS
 streaming_replica | Replication
```

Likewise, to view the databases, use:

```sh
kubectl exec -ti -c postgres cluster-example-1 -- psql -c '\l'
```

As illustrated, in addition to the default databases generated by PostgreSQL
(`postgres`, `template0`, and `template1`), CloudNativePG introduces the `app`
database, with ownership assigned to the `app` user.

```console
                                                  List of databases
   Name    |  Owner   | Encoding | Locale Provider | Collate | Ctype | ICU Locale | ICU Rules |   Access privileges
-----------+----------+----------+-----------------+---------+-------+------------+-----------+-----------------------
 app       | app      | UTF8     | libc            | C       | C     |            |           |
 postgres  | postgres | UTF8     | libc            | C       | C     |            |           |
 template0 | postgres | UTF8     | libc            | C       | C     |            |           | =c/postgres          +
           |          |          |                 |         |       |            |           | postgres=CTc/postgres
 template1 | postgres | UTF8     | libc            | C       | C     |            |           | =c/postgres          +
           |          |          |                 |         |       |            |           | postgres=CTc/postgres
(4 rows)
```

## Conclusions

This "One Cluster = One Database" approach embodies what I term the
**microservice database** paradigm. Embracing this model involves housing a
single database within a cluster. Rather than consolidating multiple databases
within a single Postgres cluster, the recommendation is to create distinct
clusters, each dedicated to a [microservice database]({{< relref "../20240228-maximizing-microservice-databases-with-k8s-postgres-cloudnativepg/index.md">}}).
Detailed insights into this strategy are available in our
[FAQ section](https://cloudnative-pg.io/documentation/current/faq/).

In this framework, the specifics of the database, such as its name and the
owning user (`app`), become less significant. The focal point shifts to the
**identity of the cluster** itself, as the `namespace:name` pair is unique in
the entire Kubernetes cluster.

That wraps up today's discussion. We've covered substantial ground, and in the
upcoming recipes, I'll delve further into our microservice database
recommendation and elucidate the default setup automatically orchestrated by
CloudNativePG through the principle of convention over configuration.

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!
