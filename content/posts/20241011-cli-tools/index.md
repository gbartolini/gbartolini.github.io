---
title: "CNPG Recipe 14 - Useful Command-Line Tools"
date: 2024-10-11T18:53:07+02:00
description: "Discover three command-line tools—`view-secret`, `view-cert`, and `stern`—to simplify managing CloudNativePG in Kubernetes. Easily inspect secrets, verify certificates, and tail logs for efficient PostgreSQL management."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "view-secret", "view-cert", "stern", "Command-line tools", "Secrets management", "TLS certificates", "Log inspection"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In this CNPG recipe, we explore three essential command-line tools that
simplify working with CloudNativePG in Kubernetes: `view-secret`, `view-cert`,
and `stern`. These tools enhance tasks such as inspecting secrets, verifying
certificates, and tailing logs across multiple pods, streamlining your
PostgreSQL management experience in a cloud-native environment. Whether you're
troubleshooting or optimising workflows, these utilities will help you boost
productivity and gain better control over your Kubernetes-based PostgreSQL
deployments._

<!--more-->

---

In this recipe, I’ll share some auxiliary tools my team at
[EDB](https://www.enterprisedb.com/) and I have discovered while working with
CloudNativePG through the command line.
By the way, the command line is still my favourite way of interacting with
PostgreSQL (cue [*"Simple Man"* by Lynyrd Skynyrd](https://youtu.be/8eNoms9wsGc?si=zcIhis-qxDRhBa-A)
playing in my ears—I’m just a `vi`, `psql`, and `kubectl` person!).

If you're familiar with CloudNativePG, you know that the main CLI isn’t a
standalone application (like other operators might have) but an extension of
the standard `kubectl` interface provided by the
[`cnpg` plugin](https://cloudnative-pg.io/documentation/current/kubectl-plugin/).
This plugin is essential for every CloudNativePG installation, significantly
improving user experience when managing PostgreSQL databases in Kubernetes. It
offers handy commands like `status`, `promote`, `destroy`, `pgbench`,
`subscriptions`, and `publications`.

In this article, however, I’ll highlight a few additional tools we’ve found
useful:

1. The [`view-secret` plugin](https://github.com/elsesiy/kubectl-view-secret)
   for kubectl
2. The [`view-cert` plugin](https://github.com/lmolas/kubectl-view-cert) for
   kubectl
3. [`stern`](https://github.com/stern/stern) for log inspection

_You can find installation instructions for each tool through the provided
links._

Before you proceed, ensure:

1. You have set up the local playground described in
   [CNPG Recipe #1](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-1-setting-up-your-local-playground-in-minutes/).
2. You’ve installed the above tools/plugins.

## The `view-secret` Plugin

The `view-secret` plugin for `kubectl` makes it much easier to decode the
content of Kubernetes secrets, which are base64-encoded by default. In
[CNPG Recipe #2](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-2-inspecting-default-resources-in-a-cloudnativepg-cluster/),
I showed how to inspect the PostgreSQL cluster secrets that CloudNativePG
generates. For example, to
[retrieve the password file for the `app` user](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-2-inspecting-default-resources-in-a-cloudnativepg-cluster/#understanding-the-app-user-secret),
you’d typically run:

```bash
kubectl get secret cluster-example-app \
  -o jsonpath="{.data.pgpass}" | base64 -d
```

With the `view-secret` plugin, you can simplify this to:

```bash
kubectl view-secret cluster-example-app pgpass
```

Returning:

```console
cluster-example-rw:5432:app:app:<password>
```

If you’d like to inspect the entire secret interactively, run:

```bash
kubectl view-secret cluster-example-app
```

To decode the entire content of the secret at once:

```bash
kubectl view-secret cluster-example-app -a
```

For all options, type `kubectl view-secret -h`.

## The `view-cert` Plugin

The `view-cert` plugin allows you to inspect Kubernetes TLS certificates stored
as secrets in a cluster. Since CloudNativePG relies on certificates for
securing communication between components, viewing these certificates directly
can aid in debugging and validating your configuration.

In [CNPG Recipe #2](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-2-inspecting-default-resources-in-a-cloudnativepg-cluster/#secrets-for-private-key-infrastructure-pki-and-transport-layer-security-tls),
I showed how to inspect the CA certificate with:

```bash
kubectl get secret cluster-example-ca \
  -o jsonpath="{.data['ca\.crt']}" | \
  base64 -d | \
  openssl x509 -text -noout
```

Using `view-cert`, you can simplify this to:

```bash
kubectl view-cert cluster-example-ca ca.crt
```

Returning:

```console
[
    {
        "SecretName": "cluster-example-ca",
        "Namespace": "default",
        "Version": 3,
        "SerialNumber": "1c00e63ee5f5da57bfcac34dc19580a3",
        "Issuer": "CN=cluster-example,OU=default",
        "Validity": {
            "NotBefore": "2024-10-11T13:43:06Z",
            "NotAfter": "2025-01-09T13:43:06Z"
        },
        "Subject": "CN=cluster-example,OU=default",
        "IsCA": true
    }
]
```

To inspect the TLS certificate for the streaming replication user, use:

```bash
kubectl view-cert cluster-example-replication
```

Returning:

```console
[
    {
        "SecretName": "cluster-example-replication",
        "Namespace": "default",
        "Version": 3,
        "SerialNumber": "8cbc357ed76e77e287a64e8b2262eb5b",
        "Issuer": "CN=cluster-example,OU=default",
        "Validity": {
            "NotBefore": "2024-10-11T13:43:06Z",
            "NotAfter": "2025-01-09T13:43:06Z"
        },
        "Subject": "CN=streaming_replica",
        "IsCA": false
    }
]
```

For all options, run `kubectl view-cert -h`.

## `stern` for Log Inspection

Log inspection is crucial for diagnosing issues in Kubernetes.
[`stern`](https://github.com/stern/stern) enhances this process by allowing you
to tail logs from multiple pods simultaneously. For CloudNativePG, which normally
runs multiple pods per PostgreSQL cluster, this is invaluable.

For example, to tail logs from all the pods in the `cluster-example` PostgreSQL
cluster and output them in JSON format, you can run:

```bash
stern -l cnpg.io/cluster=cluster-example -o ppextjson
```

`stern` is highly customisable, allowing you to choose different templates for
visualising logs, filter log entries, and improve readability with colours.
Be sure to explore their documentation thoroughly to uncover the features that
best fit your needs.

## Conclusion

The `view-secret`, `view-cert`, and `stern` tools are invaluable for working
with CloudNativePG in Kubernetes. They simplify essential tasks like inspecting
secrets, verifying certificates, and tailing logs across multiple pods. By
incorporating these tools into your workflow, you’ll not only boost your
productivity but also gain better control and insight when managing PostgreSQL
in a cloud-native environment.

Try them out in your next CloudNativePG deployment and experience the enhanced
efficiency they provide!

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Bon Soong! - Elephant "Training" in Chiang Mai, Thailand“](https://www.flickr.com/photos/cmav/8636738841)._
