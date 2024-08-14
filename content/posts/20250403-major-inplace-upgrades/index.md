---
title: "CNPG Recipe 17 - PostgreSQL In-Place Major Upgrades"
date: 2025-04-03T09:31:13+01:00
description: "How CloudNativePG implements offline in-place major upgrades of PostgreSQL"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

CloudNativePG 1.26 introduces one of its most anticipated features:
**declarative in-place major upgrades** for PostgreSQL using `pg_upgrade`. This
new approach allows you to upgrade PostgreSQL clusters by simply modifying the
`imageName` in their configuration—just like a minor version update. While it
requires brief downtime, it significantly reduces operational overhead, making
it ideal for managing **large fleets of PostgreSQL databases** in Kubernetes.
In this article, I will explore how it works, its benefits and limitations,
and cover an upgrade of a 2.2TB database.

<!--more-->

---

CloudNativePG 1.26, expected at the end of this month, introduces one of the most highly anticipated features in
the project's history: in-place major version upgrades of PostgreSQL using
`pg_upgrade`.

Unlike minor upgrades, which primarily involve applying patches, major upgrades
require handling changes to the internal storage format introduced by the new
PostgreSQL version.

This feature is now available for public testing through the preview
[1.26.0-rc1 release](https://cloudnative-pg.io/releases/cloudnative-pg-1-26.0-rc1-released/).

## An Overview of the Existing Methods

CloudNativePG now provides three declarative (yes, declarative!) methods for
performing major version upgrades. Two of these require a new cluster and are
classified as **blue/green deployment strategies**.

The first approach leverages the `import` capability with `pg_dump` and
`pg_restore`. While practical for small databases and useful for testing new
versions, the final cutover requires downtime, making it an offline upgrade.

The second method takes advantage of PostgreSQL’s native logical replication,
enabling zero-downtime upgrades—hence, an online upgrade—regardless of database
size. This remains my preferred approach for upgrading business-critical
PostgreSQL databases. It can also be used for migrations from external
environments into Kubernetes (e.g., from Amazon RDS to CloudNativePG).
For more details, see ["CloudNativePG Recipe 15 - PostgreSQL Major Online Upgrades with Logical Replication"]({{< relref "../20241210-major-online-upgrades/index.md" >}}).

The third method, and the focus of this article, is offline in-place upgrades
using `pg_upgrade`, PostgreSQL's official tool for this kind of operations.

## The Use Case for In-Place Major Upgrades

The primary motivation for introducing this feature in Kubernetes is to
eliminate the operational difference between minor and major PostgreSQL
upgrades for GitOps users. With this approach, upgrading simply requires
modifying the cluster configuration's `spec` and updating the image for all
cluster components (primary and standby servers). This is particularly
beneficial at scale—when managing dozens or even hundreds of PostgreSQL
clusters within the same Kubernetes cluster—where blue/green upgrades pose
operational challenges.

## Before You Start

In-place major upgrades are currently available for preview and testing in
[CloudNativePG 1.26.0-RC1](https://cloudnative-pg.io/documentation/preview/installation_upgrade/#directly-using-the-operator-manifest).
You can test this feature on any Kubernetes cluster, including a local setup
using `kind`, as explained in ["CloudNativePG Recipe 1 - Setting Up Your Local Playground in Minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}}).

To deploy CloudNativePG 1.26.0-RC1, run:

```sh
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.26.0-rc1.yaml
```

## How It Works

CloudNativePG allows you to specify the PostgreSQL operand image in two ways:

- Using the `.spec.imageName` option
- Using image catalogs (`ImageCatalog` and `ClusterImageCatalog` resources)

This article focuses on the `imageName` method, though the same principles
apply to the image catalog approach.

Let’s assume you have a PostgreSQL cluster running with:

```yaml
imageName: ghcr.io/cloudnative-pg/postgresql:13.20-minimal-bullseye
```

This means your cluster is using the latest available container image for
PostgreSQL 13 (minor version 20). Since PostgreSQL 13 reaches end-of-life in
November this year, you decide to upgrade to PostgreSQL 17 using the
`ghcr.io/cloudnative-pg/postgresql:17.4-minimal-bullseye` image.

By updating the `imageName` field in the cluster configuration, CloudNativePG
automatically initiates a major version upgrade.

### The Upgrade Process

The first step is safely shutting down the PostgreSQL cluster to ensure data
consistency before upgrading. This is an offline operation that incurs
downtime, but it allows modifications to static data files with full integrity.

CloudNativePG then updates the `Cluster` resource status to record the
currently running image before initiating the upgrade. This is essential for
rollback in case of failure (discussed later in the article).

After that, CloudNativePG starts a Kubernetes job responsible for preparing the
PostgreSQL data files on the Persistent Volume Claims (PVC) for the new major
version using `pg_upgrade`:

- The job creates a temporary copy of the old PostgreSQL binaries.
- It initializes a new `PGDATA` directory using `initdb` for the target
  PostgreSQL version.
- It verifies the upgrade requirement by comparing the on-disk PostgreSQL
  versions, preventing unintended upgrades based on image tags.
- It automatically remaps WAL and tablespace volumes as needed.

At this point, it runs the actual upgrade process with `pg_upgrade` and the
`--link` option to leverage hard links, significantly speeding up data
migration while minimizing storage overhead and disk I/0.

If the upgrade completes successfully, CloudNativePG replaces the original
PostgreSQL data directories with the upgraded versions, destroys the persistent
volume claims of the replicas, and restarts the cluster.

However, if `pg_upgrade` encounters an error, you will need to manually revert
to the previous PostgreSQL major version by updating the `Cluster`
specification and deleting the upgrade job. Like any in-place upgrade, there is
always a risk of failure. To mitigate this, it is crucial to maintain
continuous base backups. If your storage class supports volume snapshots,
consider taking one before initiating the upgrade—it’s a simple precaution that
could save you from unexpected issues.

Overall, this streamlined approach enhances the efficiency and reliability of
in-place major upgrades, making PostgreSQL version transitions more manageable
in Kubernetes environments.

## Example

The best way to understand this feature is to test it in practice. Let’s start
with a basic PostgreSQL 13 cluster named `pg`, defined in the following
`pg.yaml`:

```yaml
{{< include "yaml/pg-13.yaml" >}}
```

After creating the cluster, check its status with:

```sh
kubectl cnpg status pg
```

You can also verify the version with `psql`:

```sh
kubectl cnpg psql pg -- -qAt -c 'SELECT version()'
```

Returning something similar to this:

```console
PostgreSQL 13.20 (Debian 13.20-1.pgdg110+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 10.2.1-6) 10.2.1 20210110, 64-bit
```

Now, let’s upgrade from PostgreSQL 13, which is nearing end-of-life, to the
latest minor release of the most recent major version. To do this, simply
update the `imageName` field in your configuration:

```yaml
{{< include "yaml/pg-17.yaml" >}}
```

Apply the changes to trigger the major upgrade procedure:

```sh
kubectl apply -f pg.yaml
```

Once the process is complete, verify the upgrade by checking the cluster status
again. Your database should now be running PostgreSQL 17.

If you check again the version, you should now get a similar output:

```console
PostgreSQL 17.4 (Debian 17.4-1.pgdg110+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 10.2.1-6) 10.2.1 20210110, 64-bit
```

If you type `kubectl get pods` now, you will see that pods and PVCs named
`pg-2` and `pg-3` don't exist anymore, as the scale up operation replaced them
with sequence numbers 4 and 5:

```console
NAME   READY   STATUS    RESTARTS   AGE
pg-1   1/1     Running   0          62s
pg-4   1/1     Running   0          36s
pg-5   1/1     Running   0          15s
```

## Limitations and Caveats

As you have just experienced, one limitation of this implementation—though it
does not affect database access—is the need to recreate **replicas**, which is
currently supported only via `pg_basebackup`. This means that until a new
replica is available, if the primary node fails, you will need to restore from
the most recent backup. In most cases, this backup will be from the previous
PostgreSQL version, requiring you to repeat the major upgrade process.

While this scenario is unlikely, it is important to acknowledge the risk.
However, in most cases, replication completes within minutes, depending
on database complexity (primarily number of tables).

For significantly larger databases, be aware that the cluster will remain in a
degraded state for high availability until replication is fully restored. To
mitigate risk, I strongly recommend taking a physical backup as soon as
possible after the upgrade completes.

Another key consideration is **extensions**. They are an integral part of the
upgrade process. Ensure that all required extensions—and their respective
versions—are available in the target PostgreSQL version's operand image. If any
are missing, the upgrade will fail. Always validate extension compatibility
before proceeding.

## Testing a Large Database Upgrade

As part of my testing efforts, I wanted to evaluate how a major PostgreSQL
upgrade handles a large database. To do this, I created a **2.2TB** PostgreSQL
16 database using `pgbench` with a scale of **150,000**. Below is an excerpt
from the `cnpg status` command:

```console
Cluster Summary
Name                 default/pg
System ID:           7487705689911701534
PostgreSQL Image:    ghcr.io/cloudnative-pg/postgresql:16
Primary instance:    pg-1
Primary start time:  2025-03-30 20:42:26 +0000 UTC (uptime 72h32m31s)
Status:              Cluster in healthy state
Instances:           1
Ready instances:     1
Size:                2.2T
Current Write LSN:   1D0/8000000 (Timeline: 1 - WAL File: 00000001000001D000000001)
<snip>
```

I then triggered an upgrade to **PostgreSQL 17**, which completed in just **33
seconds**, restoring the cluster to full operation in under a minute. Below is
the updated `cnpg status` output:

```console
Cluster Summary
Name                 default/pg
System ID:           7488830276033003555
PostgreSQL Image:    ghcr.io/cloudnative-pg/postgresql:17
Primary instance:    pg-1
Primary start time:  2025-03-30 20:42:26 +0000 UTC (uptime 72h44m45s)
Status:              Cluster in healthy state
Instances:           1
Ready instances:     1
Size:                2.2T
Current Write LSN:   1D0/F404F9E0 (Timeline: 1 - WAL File: 00000001000001D00000003D)
```

Since CloudNativePG leverages PostgreSQL’s `--link` option (which uses hard
links), **upgrade time primarily depends on the number of tables rather than
database size**.

## Conclusions

In-place major upgrades with `pg_upgrade` bring PostgreSQL’s traditional upgrade
path into Kubernetes, giving users a declarative way to transition between
major versions with minimal operational overhead. While this method does
involve downtime, it eliminates the need for blue/green clusters, making it
particularly well-suited for environments managing a **large fleet of small to
medium-sized PostgreSQL instances**.

If the upgrade succeeds, you have a fully functional PostgreSQL cluster, just
as if you had run `pg_upgrade` on a traditional VM or bare metal instance. If it
fails, rollback options are available—including reverting to the original
manifest and deleting the upgrade job. If necessary, continuous backups provide
an additional safety net.

Although in-place upgrades may not be my preferred method for mission-critical
databases, they provide an important option for teams that prioritise
**operational simplicity and scalability** over achieving zero-downtime
upgrades. As demonstrated in testing, upgrade times primarily depend on the
number of tables rather than database size, making this approach efficient even
for large datasets.

The **success of this feature relies on real-world feedback**. We encourage you
to test and validate it during the release candidate phase to ensure
CloudNativePG 1.26.0 is robust and production-ready—especially when using
extensions. Your insights will directly influence its future, so let us know
what you think!

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

<!--
_Cover Picture: [“Indian Elephant Photo - Kalyan Varma“](https://animalia.bio/indian-elephant)._
-->

