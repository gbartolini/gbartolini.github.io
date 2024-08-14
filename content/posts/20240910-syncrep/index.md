---
title: "CNPG Recipe 13 - Configuring PostgreSQL synchronous replication"
date: 2024-09-10T09:30:00+02:00
description: ""
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes"]
cover: cover.jpg
thumb: thumb.jpg
draft: true
---

_ABSTRACT_

<!--more-->

---

CloudNativePG 1.24 introduces a highly customisable approach to managing
synchronous replication in a PostgreSQL cluster through the new
`.spec.postgresql.synchronous` stanza.

This new method, which is the focus of this article, will eventually replace
the existing approach that uses `minSyncReplicas` and `maxSyncReplicas` for
quorum-based synchronous replication.

Key improvements in CloudNativePG include:

- Support for both quorum-based and priority-based synchronous replication
- Enhanced control over the PostgreSQL `synchronous_standby_names` parameter
  (GUC)

In a typical synchronous replication setup within a single `Cluster` resource
spanning multiple availability zones, quorum-based replication is highly
effective. The operator automatically manages `synchronous_standby_names` based
on the active PostgreSQL instance pods, making it well-suited for cloud
environments.

However, when synchronous replication is required across external clusters, a
priority-based approach may provide greater control and flexibility. This
method allows for more fine-grained customization of
`synchronous_standby_names`, but it also comes with certain limitations and
trade-offs that need to be carefully considered. Such a configuration is common
in on-premise deployments, where instead of a stretched Kubernetes cluster, two
single-AZ Kubernetes clusters are used.

## Internal Synchronous Replication (Within the Cluster)

To minimise the risk of data loss in a highly available `Cluster` managed by
CloudNativePG, configuring synchronous replication is essential. In such
environments, where CloudNativePG treats all instances equally, quorum-based
synchronous replication is the recommended approach. It offers a balanced
compromise between data safety and performance, enhancing overall data
durability.

PostgreSQL’s quorum-based synchronous replication ensures that a transaction
commit only succeeds once its Write-Ahead Log (WAL) records have been
replicated to a specified number of replicas. The replication order is
irrelevant, as PostgreSQL self-regulates by acknowledging the fastest
responders.

CloudNativePG simplifies the management of the `synchronous_standby_names`
parameter by automatically keeping it up to date throughout the PostgreSQL
`Cluster` lifecycle. The configuration dynamically adjusts based on the
`.spec.postgresql.synchronous` stanza and the active instance pods in the
cluster, ensuring seamless, reliable replication management.

The following example demonstrates how to deploy a 3-instance `Cluster` with
quorum-based synchronous replication enabled. In this configuration, the
cluster requests that at least one replica acknowledges transactions using the
`method: any` and `number: 1` settings.

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

Once the cluster is deployed, CloudNativePG automatically configures Postgres'
`synchronous_standby_names` setting as `ANY 1 ("angus-2","angus-3")`.
This configuration ensures that a transaction commit will wait for
acknowledgment from any one of the listed replicas. We'll delve deeper into the
concept of "receipt confirmation" later in this article, specifically when
discussing PostgreSQL's `synchronous_commit` configuration option.

## External Synchronous Replication (Beyond the Cluster)

In some scenarios, it’s essential to replicate data beyond a single Kubernetes
cluster. This is particularly pertinent for on-premise deployments involving
two separate Kubernetes clusters in close proximity.

For example, suppose we have a [CloudNativePG replica cluster](https://cloudnative-pg.io/documentation/current/replica_cluster/)
named `brian` in a second Kubernetes cluster, replicating from a primary
cluster named `angus`. We want to ensure that the designated primary in the
`brian` cluster, which is replicating directly from `angus-rw`, is included in
the synchronous replication process. Specifically, we aim to secure data both
in another instance of the `angus` cluster and in the designated primary of the
`brian` cluster.

Assuming the `brian` replica cluster is correctly configured, you can achieve
this setup with the following manifest excerpt:

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

This configuration will initially set `synchronous_standby_names` to `ANY 1
("brian", "angus-2")`.

## Configuring `synchronous_commit`

When committing a transaction, it is typically important to ensure that data is
securely written to disk in the Write-Ahead Log (WAL) and `fsync`ed before
returning success and handing control back to the application.

In a high-availability cluster with a primary and multiple standbys, you can
increase this level of safety by requiring that the transaction data is also
durably stored on one or more replicas.

This behavior in PostgreSQL is controlled by the `synchronous_commit` setting,
which is closely tied to the `synchronous_standby_names` configuration.

It's important to note that `synchronous_commit` can be overridden at the
transaction level in PostgreSQL, via the [`SET` command](https://www.postgresql.org/docs/current/sql-set.html).
This allows you to define a default behavior for the system while giving
developers the flexibility to adjust the durability settings for specific
transactions as needed.

> Note: `fsync` must always be enabled (`on`) in production environments.

### Asynchronous Replication

If `synchronous_standby_names` is empty (indicating asynchronous replication),
`synchronous_commit` can take two values:

- **`off`**: Success is returned immediately after writing to WAL on the
  primary, without guaranteeing that data is written to disk. This can lead to
  potential data loss in the event of a failure.
- **`on`**: Success is returned only after WAL data is written and secured on
  disk (this is the default behavior). However, it only ensures local
  durability on the primary.

The diagram below illustrates the two levels of durability that can be
guaranteed with the `synchronous_commit` setting in an asynchronous replication
on the primary instance only.

![`synchronous_commit` levels in asynchronous replication contexts](images/01-async.png)

### Synchronous Replication

If `synchronous_standby_names` is not empty (indicating synchronous
replication, either quorum-based or priority-based), `synchronous_commit`
offers more options to control how and when the primary waits for standby
acknowledgment.
These options are arranged in ascending order of data durability, allowing you
to balance performance with reliability:

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

The diagram below illustrates the various levels of durability that can be
achieved with the `synchronous_commit` setting in a synchronous replication
scenario.

![`synchronous_commit` levels in synchronous replication contexts](images/02-sync.png)

For more information, you can refer to the
[official PostgreSQL documentation](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT).


## Conclusions

By now, you should have a clearer understanding of how to configure synchronous
replication with CloudNativePG, whether within a single Kubernetes cluster
(internal) or across multiple clusters (external). While you cannot directly
manipulate the `synchronous_standby_names` setting, CloudNativePG provides a
powerful and flexible abstraction through the `synchronous` stanza.

You can adjust the `synchronous_commit` option based on the desired level of
durability, allowing developers to fine-tune it at the transaction level to
meet the specific needs of your environment.

Looking ahead, CloudNativePG aims to enhance its support for synchronous
replication by introducing the ability to set a priority on the underlying
Kubernetes nodes. This would influence how the `synchronous_standby_names` list
is constructed, enabling the use of priority-based synchronous replication
within a PostgreSQL cluster. Such a feature could also open up interesting
possibilities, like serving consistent reads through a service targeting the
primary and priority-based replicas. While this remains a future vision, the
current capabilities are already well-suited for most use cases.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephants Playing with each other with pushes by there heads“](https://commons.wikimedia.org/wiki/File:Elephants_Play.jpg)._

