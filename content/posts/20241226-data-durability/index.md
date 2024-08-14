---
title: "CNPG Recipe 16 - Balancing Data Durability and Self-Healing with Synchronous Replication"
date: 2024-12-26T10:57:00+01:00
description: "Explore how CloudNativePG 1.25 introduces data durability control to strike the right balance between consistency and availability in PostgreSQL clusters."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_CloudNativePG 1.25 enhances control of PostgreSQL synchronous replication with
a new dataDurability option, allowing you to choose between prioritising data
consistency or self-healing capabilities. This article explains the feature,
contrasts it with previous approaches, and provides guidance on migrating to
the new API format._

<!--more-->

---

In ["CNPG Recipe 13 - Configuring PostgreSQL Synchronous Replication"]({{< relref "../20240910-syncrep/index.md" >}}),
I provided a comprehensive overview of how PostgreSQL synchronous replication
is implemented in CloudNativePG. This article builds on that foundation by
introducing a new feature available in [CloudNativePG 1.25](https://cloudnative-pg.io/releases/cloudnative-pg-1-25.0-released/):
**data durability control** for internal synchronous replication within a
PostgreSQL cluster.

## Addressing the Missing Piece in 1.24

As detailed in ["CNPG Recipe 13"]({{< relref "../20240910-syncrep/index.md" >}}),
CloudNativePG 1.24 introduced a new API for managing synchronous replication,
marking the beginning of the
[deprecation process for the previous method based on `minSyncReplicas` and `maxSyncReplicas`](https://cloudnative-pg.io/documentation/current/replication/#synchronous-replication-deprecated).

However, a significant difference existed between the old and new methods in
terms of data durability:

- The previous approach, based on `minSyncReplicas` and `maxSyncReplicas`,
  prioritised self-healing over data durability. If no replicas were available,
  CloudNativePG would automatically disable synchronous replication to maintain
  availability.
- In contrast, the new API prioritised data durability. Write operations would
  hang if no synchronous replica was available, ensuring consistency but
  potentially impacting availability.

From my discussions with CloudNativePG users, the first option typically
appeals to platform engineers focused on achieving large-scale self-healing and
high availability, while the second aligns with the expectations of synchronous
replication from a DBA's perspective.

CloudNativePG 1.24 lacked an option to balance these two approaches, leaving
users unable to choose between prioritising data durability or self-healing.

This limitation also hindered migration to the new synchronous replication API
for users who relied on self-healing capabilities.

## The `dataDurability` Option in CloudNativePG 1.25

CloudNativePG 1.25 introduces the `dataDurability` option in the
`.spec.postgresql.synchronous` stanza, enabling users to configure the
durability mode for synchronous replication.

This option allows a choice between two modes:

- `required` (*default*): Ensures strict data consistency and durability,
  aligning with PostgreSQL's behaviour. This mode maintains compatibility with
  the behaviour in CloudNativePG 1.24.
- `preferred`: Focuses on self-healing and high availability by automatically
  disabling synchronous replication when no replicas are available in the
  cluster. This mode bridges the gap between the new API for synchronous
  replication control and the previous approach based on `minSyncReplicas` and
  `maxSyncReplicas`.

## Migrating to the New Format

After upgrading to CloudNativePG 1.25, it is recommended to update your
cluster's configuration for synchronous replication based on `minSyncReplicas`
and `maxSyncReplicas` to the new API format based on the
`postgresql.synchronous` stanza.

For example, you can safely replace the following configuration:

```yaml
  # <snip>
  minSyncReplicas: 1
  maxSyncReplicas: 1
  # <snip>
```

With the updated format:

```yaml
  # <snip>
  postgresql:
    synchronous:
      method: any
      number: 1
      dataDurability: preferred
  # <snip>
```

This configuration maintains the same behaviour as the previous approach using
`minSyncReplicas` and `maxSyncReplicas`, while also prioritising self-healing.

To shift the focus to data consistency, simply update the configuration to use
`dataDurability: required` in the snippet above. This allows you to align with
stricter durability requirements as needed from a DBA standpoint.

Upgrade today to CloudNativePG and enjoy this new feature!

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephants“ (public domain)](https://www.needpix.com/photo/66726/)._

