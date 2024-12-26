---
title: "CNPG Recipe 13 - Configuring PostgreSQL Synchronous Replication"
date: 2024-09-10T10:12:30+02:00
description: "Configuring PostgreSQL synchronous replication with CloudNativePG to balance data durability and performance"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "synchronous replication", "quorum", "priority", "any", "first", "data durability", "high availability", "synchronous_commit", "synchronous_standby_names", "write-ahead log", "wal", "fsync", "remote_apply", "remote_write"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_CloudNativePG 1.24 introduces a highly customisable approach to managing
PostgreSQL synchronous replication through the new `.spec.postgresql.synchronous`
stanza. In this article, I’ll guide you through configuring synchronous
replication within a single Kubernetes cluster and across multiple clusters.
I’ll explore quorum-based and priority-based replication methods, highlighting
their benefits and trade-offs. Additionally, I’ll explain how to adjust the
`synchronous_commit` setting to strike the right balance between data
durability and performance._

<!--more-->

_NOTE: This article was updated on December 26, 2024, to include a link to
[CNPG Recipe #16]({{< relref "../20241226-data-durability/index.md" >}}), which
covers the new `dataDurability` option introduced in CloudNativePG 1.25._

---

CloudNativePG 1.24 introduces a highly customisable approach to managing
synchronous replication in PostgreSQL clusters through the new
`.spec.postgresql.synchronous` stanza.

This new method, which is the focus of this article, will eventually replace
the existing approach using `minSyncReplicas` and `maxSyncReplicas` for
quorum-based synchronous replication starting from CloudNativePG 1.25,
as explained in a more recent article:
[CNPG Recipe #16 - Balancing Data Durability and Self-Healing with Synchronous Replication]({{< relref "../20241226-data-durability/index.md" >}}).

## Key improvements

Key improvements in CloudNativePG include:

- Support for both quorum-based and priority-based synchronous replication
- Enhanced control over the PostgreSQL `synchronous_standby_names` parameter
  (GUC)

In a typical synchronous replication setup within a single `Cluster` resource
spanning multiple availability zones, quorum-based replication is highly
effective. The operator automatically manages the `synchronous_standby_names`
parameter based on active PostgreSQL instance pods, making it ideal for cloud
environments.

However, when synchronous replication is required across external clusters, a
priority-based approach may offer greater control and flexibility. This method
allows for more fine-tuned customisation of `synchronous_standby_names`, but it
also involves certain limitations and trade-offs. Such a configuration is
typical in on-premise deployments where, instead of a stretched Kubernetes
cluster, two separate single-AZ Kubernetes clusters are used.

## Internal Synchronous Replication (Within the Cluster)

To minimise the risk of data loss in a highly available `Cluster` managed by
CloudNativePG, configuring synchronous replication is essential. In these
environments, where all instances are treated equally, quorum-based synchronous
replication is the recommended approach. It strikes a balance between data
safety and performance, enhancing overall data durability.

PostgreSQL’s quorum-based synchronous replication ensures that a transaction
commit only succeeds once its Write-Ahead Log (WAL) records have been
replicated to a specified number of replicas. The replication order is
irrelevant, as PostgreSQL self-regulates by acknowledging the fastest
responders.

CloudNativePG simplifies managing the `synchronous_standby_names` parameter by
keeping it automatically updated throughout the lifecycle of a PostgreSQL
`Cluster`. The configuration dynamically adjusts based on the
`.spec.postgresql.synchronous` stanza and the active instance pods, ensuring
reliable replication management.

Here’s an example of a 3-instance `Cluster` with quorum-based synchronous
replication enabled. In this setup, the cluster requires at least one replica
to acknowledge transactions using the `method: any` and `number: 1` settings.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: angus
spec:
  instances: 3

  storage:
    size: 1G

  postgresql:
    synchronous:
      method: any
      number: 1
```

Once deployed, CloudNativePG configures PostgreSQL’s
`synchronous_standby_names` to `ANY 1 ("angus-2", "angus-3")`. This ensures
that a transaction commit waits for acknowledgment from any one of the listed
replicas. We’ll explore the concept of "receipt confirmation" ((successful
acknowledgment)) later when discussing PostgreSQL’s `synchronous_commit`
configuration option.

## External Synchronous Replication (Beyond the Cluster)

In some scenarios, data replication is required beyond a single Kubernetes
cluster. This is especially relevant in on-premise deployments with two
separate Kubernetes clusters in close proximity.

For instance, consider a [CloudNativePG replica cluster](https://cloudnative-pg.io/documentation/current/replica_cluster/)
named `brian` in a second Kubernetes cluster, replicating from a primary
cluster called `angus`. We want to ensure the designated primary in the `brian`
cluster, which replicates directly from `angus-rw`, participates in synchronous
replication. Specifically, we aim to secure data in both another instance of
the `angus` cluster and the designated primary of the `brian` cluster.

Assuming the `brian` replica cluster is correctly configured, you can achieve
this architecture with the following manifest:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: angus
spec:
  instances: 3

  # <snip>
  postgresql:
    synchronous:
      method: first
      number: 2
      maxStandbyNamesFromCluster: 1
      standbyNamesPre:
      - brian
  # <snip>
```

This configuration will initially set `synchronous_standby_names` to
`FIRST 2 ("brian", "angus-2")`. By setting `maxStandbyNamesFromCluster` to `1`,
we ensure that only one instance from the `angus` cluster (initially `angus-2`)
is included in the `synchronous_standby_names` list, following `brian`, which
is prioritised as specified in the `standbyNamesPre` section.

It's important to understand that the `angus` cluster has no control over the
`brian` cluster. It's your responsibility to ensure that `brian` is properly
monitored and consistently available to prevent blocking write operations on
the primary.

## Configuring `synchronous_commit`

When committing a transaction, it’s crucial to ensure that data is securely
written to disk in the Write-Ahead Log (WAL) and `fsync`ed before returning
success to the application.

In a high-availability cluster with a primary and multiple standbys, you can
increase safety by ensuring the transaction data is durably stored on one or
more replicas. PostgreSQL’s `synchronous_commit` setting controls this behaviour
and works closely with the `synchronous_standby_names` parameter.

Notably, `synchronous_commit` can be overridden at the transaction level using
the [`SET` command](https://www.postgresql.org/docs/current/sql-set.html),
allowing for flexibility in durability based on the needs of individual
transactions.

> **Note:** In production environments, `fsync` should always be set to `on`.

### Asynchronous Replication

When `synchronous_standby_names` is empty (indicating asynchronous
replication), `synchronous_commit` offers two options:

- **`off`**: Success is returned immediately after writing to WAL on the
  primary, without guaranteeing data is written to disk. This increases the
  risk of data loss in case of failure.
- **`on`**: Success is returned after WAL data is written and secured on disk
  (default behaviour). However, this ensures durability only on the primary.

The diagram below illustrates the two levels of durability achievable with
`synchronous_commit` in an asynchronous replication context.

![`synchronous_commit` levels in asynchronous replication contexts](images/01-async.png)

### Synchronous Replication

If `synchronous_standby_names` is not empty, `synchronous_commit` provides more
options to control how and when the primary waits for standby acknowledgment.
These options, arranged by increasing data durability, let you strike a balance
between performance and reliability:

- **`off`**: Same as in asynchronous replication.
- **`local`**: Success is returned once the WAL is written and secured on disk
  on the primary. No confirmation from replicas is required, even in
  synchronous replication mode.
- **`remote_write`**: Success is returned once the WAL is written to the memory
  of the required number of replicas (based on `synchronous_standby_names`),
  but before it is flushed to disk. This offers a trade-off between performance
  and durability, as data is transmitted to the replica but not yet fully
  committed on disk.
- **`on`**: Success is returned after the WAL has been written and flushed to
  disk on both the primary and the required number of replicas (based on
  `synchronous_standby_names`). This ensures full durability across the cluster.
- **`remote_apply`**: Success is returned only after the transaction has been
  applied (made visible) on the required number of synchronous replica(s).
  This provides the highest level of consistency, guaranteeing that any read on
  a synchronous replica will reflect the committed transaction. While it may
  impact write performance, it is beneficial during automated failover, as it
  ensures the standby replica being promoted has the most up-to-date transaction
  state, reducing recovery time.

The diagram below demonstrates the durability levels achievable with
`synchronous_commit` in synchronous replication scenarios, before "receipt
confirmation" is sent to the primary.

![`synchronous_commit` levels in synchronous replication contexts](images/02-sync.png)

For further information, refer to the
[PostgreSQL documentation](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT).

Options such as `remote_write`, `on`, and `remote_apply` in PostgreSQL's
synchronous replication significantly reduce the risk of data loss in the event
of a sudden primary failure. These settings ensure that transactional data is
not only written to the primary but also securely stored on one or more
replicas, effectively guaranteeing a recovery point objective (RPO) of zero in
a highly available cluster. This means that no committed transaction will be
lost during failover.

> **Note:** While PostgreSQL’s synchronous replication provides strong
> consistency, it's important to be aware of rare edge cases. For instance, a
> replica may send "receipt confirmation" to the primary, but if the primary
> fails immediately before passing this confirmation back to the application,
> there is a potential for the transaction to be perceived as incomplete or
> lost by the application. Despite these corner cases, synchronous replication
> remains one of the best tools for achieving high data durability.

## Conclusions

By now, you should have a better understanding of how to configure synchronous
replication with CloudNativePG, both within a single Kubernetes cluster
(internal) and across multiple clusters (external). While direct manipulation
of `synchronous_standby_names` is unavailable, CloudNativePG’s `synchronous`
stanza provides a flexible and powerful abstraction.

Depending on your required durability level, you can adjust the
`synchronous_commit` setting and allow developers to fine-tune it at the
transaction level to suit specific needs.

In the future, CloudNativePG plans to introduce node prioritisation, which
would influence how the `synchronous_standby_names` list is built. This could
enable priority-based synchronous replication within PostgreSQL clusters and
open up new possibilities, such as serving consistent reads through services
targeting primary and priority-based replicas. While this is still a vision,
the current capabilities are more than sufficient for the vast majority of use
cases.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephants Playing with each other with pushes by there heads“](https://commons.wikimedia.org/wiki/File:Elephants_Play.jpg)._

