---
title: "CloudNativePG Recipe 8: Participating in PostgreSQL 17 Testing Program in Kubernetes"
date: "2024-06-10T15:09:19+02:00"
description: "Participate in the PostgreSQL 17 beta and release candidate program using Kubernetes and CloudNativePG"
tags: ["PostgreSQL", "postgres", "open source", "pre-release", "pg17", "beta", "release candidate", "PostgreSQL 17", "Beta 3", "CloudNativePG", "Kubernetes", "PGDG", "Operand container images", "Postgres container", "Image registry", "17beta3", "17", "Debian 12", "Bookworm", "Debian 11", "Bullseye", "pgaudit", "pg_failover_slots", "Testing program", "Performance improvements", "Benchmarks", "Release candidate"]
cover: cover.png
thumb: thumb.png
draft: false
---

_Join the PostgreSQL 17 testing program using Kubernetes and CloudNativePG!
With the recent release of PostgreSQL 17 Beta, our community has made operand
container images available for testing. This article guides you through
deploying a PostgreSQL 17 cluster, selecting specific Debian versions, and
verifying installations. Perfect for developers in early stages, your
participation will help identify and fix bugs before the final release. Get
involved and ensure PostgreSQL 17 is robust and ready for production, even in
Kubernetes!_


_... or thanks to Kubernetes! ;)_

<!--more-->

_NOTE: PostgreSQL 17 has been released since this article was published._
<!--
_NOTE: this article has been updated on August 14, 2024 with PostgreSQL Beta 3
and the most recent versions of `kind` and `cloudnative-pg`._
-->


---

In May, the PostgreSQL Global Development Group (PGDG) released [PostgreSQL 17 Beta 1](https://www.postgresql.org/about/news/postgresql-17-beta-1-released-2865/),
providing a preview of the features expected in the final release of PostgreSQL
17 later this year (see the [release notes](https://www.postgresql.org/docs/17/release-17.html)).
On August 8th, the PGDG released [PostgreSQL 17 Beta 3](https://www.postgresql.org/about/news/postgresql-164-158-1413-1316-1220-and-17-beta-3-released-2910/),
continuing the beta testing phase.

If you're interested in trying CloudNativePG on your laptop, follow
["CNPG Recipe #1 - Setting Up Your Local Playground in Minutes"]({{< relref "../20240303-recipe-local-setup/index.md">}})
and adjust the image name in the cluster definition as described in the rest of
this article.
Additionally, consider testing [CloudNativePG 1.24.0 RC1](https://cloudnative-pg.io/documentation/preview/installation_upgrade/),
which includes [support for some PostgreSQL 17 features](https://cloudnative-pg.io/releases/cloudnative-pg-1-24.0-rc1-released/).

My personal recommendation goes to all application developers who are now at
the early stage of their application development process and planning to go
into production sometime next year: start using PostgreSQL 17 in your tests
now.

## Container Images

As part of the CloudNativePG community, we have made operand container images
for PostgreSQL 17 Beta 3 available in our official
[`postgres-container` image registry](https://github.com/cloudnative-pg/postgres-containers/pkgs/container/postgresql).
These images, tagged with '17beta3', are specifically designed for use
with the CloudNativePG operator and are not intended for production
environments.

To select a specific Debian version, use the `-NAME` suffix, where `NAME` is
either:

- `bookworm`, for [Debian 12](https://www.debian.org/releases/bookworm/)
- `bullseye`, for [Debian 11](https://www.debian.org/releases/bullseye/)

For instance, to run PostgreSQL 17 Beta 3 on Debian 12, you would use the image
tag `ghcr.io/cloudnative-pg/postgresql:17beta3-bookworm`.
Alternatively, if you want to test the latest beta version on Debian 12, you
could use the image tag `ghcr.io/cloudnative-pg/postgresql:17beta-bookworm`.

Currently, these images do not include the `pgaudit` and `pg_failover_slots`
extensions, as the necessary packages for PostgreSQL 17 are not yet available.

We invite you to join us in testing the new features of PostgreSQL 17 with
CloudNativePG. Your participation will help us identify and fix bugs in
PostgreSQL before its final release.

Specifically, since each new PostgreSQL version comes with performance
improvements, I am very interested in running the same
[benchmarks that I presented at KubeCon EU in Paris a few months ago on PostgreSQL 17]({{< relref "../20240408-volume-scaling-1/index.md">}}).

## Example

Below is a quick example of a 3-instance PostgreSQL 17 'Cluster' manifest for
deployment in your Kubernetes cluster:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg17
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:17beta3-bookworm
  instances: 3
  storage:
    size: 1Gi
```

After deploying, you can verify the version with the following command:

```shell
kubectl exec -ti pg17-1 -c postgres -- psql -qAt -c 'SELECT version()'
```

This should return:

```console
PostgreSQL 17beta3 (Debian 17~beta3-1.pgdg120+1) on x86_64-pc-linux-gnu,
  compiled by gcc (Debian 12.2.0-14) 12.2.0, 64-bit
```

## Conclusion

In the coming weeks, more beta versions and at least one release candidate
version will be published by the PGDG. It goes without saying that we should
all use the latest pre-release version when testing (`beta3` at the time of
writing this article).

While PostgreSQL 17 can be run in CloudNativePG, we are actively working on
integrating some of the new features introduced in PostgreSQL 17 into
CloudNativePG. These enhancements are targeted for inclusion in versions 1.24
and 1.25, which will offer official support once PostgreSQL 17 is in
production.

Join me and the rest of the PostgreSQL Community in this testing program to
ensure PostgreSQL 17 is robust and ready for its official release! Thank you!

