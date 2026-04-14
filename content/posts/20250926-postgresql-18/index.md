---
title: "Run PostgreSQL 18 on Kubernetes Today with CloudNativePG"
date: 2025-09-26T13:30:38+02:00
description: "Run the new PostgreSQL 18 on Kubernetes in minutes with CloudNativePG and our new half-sized minimal image."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "pg18", "postgresql 18", "minimal images"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_PostgreSQL 18 is officially released, packed with improvements for
performance, authentication, operations, and security. In this article, I'll
show you how to run it on Kubernetes from day one with CloudNativePG. I will
summarise key new features like asynchronous I/O and OAuth 2.0, as well as the
`extension_control_path` parameter. This is a simple but critical feature for
operational control in cloud-native environments, and one our team at
CloudNativePG and EDB was proud to help contribute to PostgreSQL. You'll see how
this reflects our close collaboration with the upstream community, learn about
our new half-sized `minimal` container image, and be able to follow my
guide to deploy your first cluster today._

<!--more-->

---

This Thursday, 25 September 2025, marks the
[official release of **PostgreSQL 18**](https://www.postgresql.org/about/news/postgresql-18-released-3142/),
the world’s most advanced open-source database. Every major release of
[PostgreSQL](https://www.postgresql.org/) is an important milestone for our
community — and this one brings exciting improvements in performance,
authentication, and security. You can find the full list of changes in the
[PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html).

Good news: with CloudNativePG and the updated
[`postgres-containers`](https://github.com/cloudnative-pg/postgres-containers),
you can run PostgreSQL 18 on Kubernetes today — using a new `minimal` image
that’s nearly half the size of PostgreSQL 17.

---

## PostgreSQL 18 in Brief

PostgreSQL 18 is packed with features that enhance performance, security, and
operational management. Among the most notable improvements for cloud-native
environments are:

- **Asynchronous I/O subsystem**: This fundamental change unlocks significant
  performance gains for I/O-bound operations like sequential scans, `VACUUM`,
  and bitmap heap scans, making workloads on large databases much faster.

- **B-tree skip scans**: Multi-column indexes can now be used even when the
  leading column isn't part of the query predicate, potentially eliminating the
  need for many specialised indexes and saving significant storage space.
  Relevant for very large databases (VLDBs).

- **OAuth 2.0 authentication**: A major step forward for modern identity
  integration, simplifying secure access in complex enterprise environments.
  I'll be covering this topic at the upcoming
  [KubeCon North America in Atlanta (November 2025)](https://kccncna2025.sched.com/event/27FXv).

- **Trusted path for extension installation (`extension_control_path`)**: As a
  strong advocate and reviewer for this feature, I believe it's a critical step
  forward for PostgreSQL's future in cloud-native, immutable infrastructures.
  This parameter allows administrators to define a specific, trusted, and
  possibly read-only directory for extension control files. This perfectly aligns
  with the declarative management model of CloudNativePG and the new "image
  volumes" feature in Kubernetes. You can read a deep dive in my previous article
  [“The Immutable Future of PostgreSQL Extensions in Kubernetes with CloudNativePG”]({{< relref "../20250303-volume-source-extension-control-path/index.md" >}}).

- **Minor but useful additions**: `postgres_fdw` can now forward client-side
  SCRAM authentication to remote servers, and the new `fips_mode()` function
  makes it easy to verify if the server is running in FIPS-compliant mode.

It is also important to mention that PostgreSQL 18 finally deprecates
**MD5 password authentication**, pushing the ecosystem toward more secure
defaults.

---

## CloudNativePG and `postgres-containers`

CloudNativePG is ready to run PostgreSQL 18. Part of its ecosystem is the
[`postgres-containers`](https://github.com/cloudnative-pg/postgres-containers)
project, where the CloudNativePG community builds and maintains container
images for PostgreSQL.

For PostgreSQL 18, we’ve introduced
[a change in the building system](https://github.com/cloudnative-pg/postgres-containers/pull/311)
that makes the `minimal` image particularly lightweight:

- **PostgreSQL 17 `minimal` image**: \~412 MB
- **PostgreSQL 18 `minimal` image**: \~232 MB

The difference comes from
[a new package called `postgresql-18-jit`](https://www.postgresql.org/message-id/20250224134829.286cc256%40ardentperf.com),
which contains LLVM JIT support. This package has been moved out of the `minimal`
image and is now included in the `standard` image, which is built on top of
the `minimal`.

This design keeps the `minimal` image lean for those who want fast pulls and
smaller footprints with reduced attack surface, while still making JIT
available when needed through the standard image.

## Hands-on: Create a PostgreSQL 18 Cluster with the `minimal` Image

> **NOTE:** You’ll need a Kubernetes environment for this hands-on.
> The easiest way to get started is with `kind`; follow
> [“CloudNativePG Recipe 1 – Setting up your local playground in minutes”]({{< relref "../20240303-recipe-local-setup/index.md" >}})
> to have one ready quickly.

Running PostgreSQL 18 on Kubernetes with CloudNativePG is straightforward.
Below is a simple example showing how to deploy a cluster using the `minimal`
image on Debian Trixie (13, current `stable` release).

1. **Create a `Cluster` manifest** (`angus.yaml`)

```yaml
{{< include "yaml/angus.yaml" >}}
```

2. **Apply the manifest**

```bash
kubectl apply -f angus.yaml
```

3. **Check cluster status**

```bash
kubectl cnpg status angus
```

You should see your cluster up and running with PostgreSQL 18.

4. **Connect and verify**

```bash
kubectl cnpg psql angus -- -c 'SELECT version()'
```

You’ll see confirmation that you’re running PostgreSQL 18 inside Kubernetes.

```console
                                                         version
--------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 18.0 (Debian 18.0-1.pgdg13+3) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```

# Conclusion

PostgreSQL 18 is here, and with CloudNativePG, you can run it on Kubernetes
right away. The `postgres-containers` project delivers fresh, secure
images—including a streamlined `minimal` variant—enabling you to test the
latest features and prepare for production from day one.

This rapid, day-one availability is no accident. As you can see, the
CloudNativePG community works very closely with the PostgreSQL project, not
just as users but as active contributors. This deep involvement allows us to
anticipate changes and even help shape features—like the new
`extension_control_path`—that are vital for running PostgreSQL securely and
efficiently in modern, cloud-native environments. We are committed to bridging
these two worlds and delivering the best possible PostgreSQL experience on
Kubernetes.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!
