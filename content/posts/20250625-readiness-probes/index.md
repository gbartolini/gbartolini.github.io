---
title: "CNPG Recipe 20 – Finer Control of Postgres Clusters with Readiness Probes"
date: 2025-06-25T08:04:00+02:00
description: "how CloudNativePG leverages Kubernetes readiness probes to give users more reliable and configurable control over PostgreSQL in high-availability clusters"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "probes", "cncf", "startup", "pg_isready", "readiness", "streaming", "maximumLag"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_Explore the new readiness probe introduced in CloudNativePG 1.26, which
advances Kubernetes-native lifecycle management for PostgreSQL. Building on the
improved probing infrastructure discussed in my previous article, this piece
focuses on how readiness probes ensure that only fully synchronised and healthy
instances—particularly replicas—are eligible to serve traffic or be promoted to
primary. Special emphasis is placed on the `streaming` probe type and its
integration with synchronous replication, giving administrators
fine-grained control over failover behaviour and data consistency._

<!--more-->

---

In the previous article —
[CNPG Recipe 19 - Finer Control Over Postgres Startup with Probes]({{< relref "../20250617-startup-probes/index.md" >}})
— I covered the first set of enhancements to the
[probing infrastructure in CloudNativePG 1.26](https://github.com/cloudnative-pg/cloudnative-pg/pull/6623),
focusing on the startup process of a Postgres instance.

In this follow-up, I’ll continue the discussion with a closer look at
CloudNativePG’s brand-new **readiness probe**.

---

## Understanding Readiness Probes

[Readiness probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/#readiness-probe)
have been part of Kubernetes since the beginning. Their purpose is to determine
whether a running container is *ready* to accept traffic—for example, whether
it should be included in a `Service`’s endpoints.

Unlike the startup probe, which runs only once at container start, the
readiness probe kicks in *after* the startup probe succeeds and continues
running for the entire lifetime of the container.

As mentioned in the previous article, readiness probes share the same
configuration parameters as startup and liveness probes:

- `failureThreshold`
- `periodSeconds`
- `successThreshold`
- `timeoutSeconds`

---

## Why Readiness Probes Matter for Postgres

Readiness probes play a critical role in ensuring that only Postgres instances
fully prepared to handle client connections are exposed through Kubernetes
Services.
They prevent traffic from being routed to pods that may be technically running
but are still recovering, replaying WAL files, or catching up as replicas.

Beyond traffic management, the concept of readiness can also be extended to
evaluate a replica’s eligibility for promotion—a direction we’ve taken in
CloudNativePG, as I’ll explain later in this article.

## How CloudNativePG Implements Readiness Probes

Unlike startup probes, CloudNativePG ships with a fixed default configuration
for readiness probes:

```yaml
failureThreshold: 3
periodSeconds: 10
successThreshold: 1
timeoutSeconds: 5
```

By default, the probe uses the `pg_isready` utility to determine whether the
Postgres instance is ready—just like the startup probe; if `pg_isready` fails
three consecutive times, with a 10-second interval between attempts, the
`postgres` container is marked as *not ready*.

However, you can fully customise the readiness probe by defining the
`.spec.probes.readiness` stanza in your cluster configuration—just like the
[*Advanced mode* described in the startup probe article]({{< relref "../20250617-startup-probes/index.md#advanced-mode-full-probe-customisation" >}}).

## Full Probe Customisation

For scenarios that require finer control, CloudNativePG allows you to customise
the readiness probe through the `.spec.probes.readiness` stanza. This lets you
explicitly define the probe parameters introduced earlier in this article.

The following example configures Kubernetes to:

- Probe the container every 10 seconds (`periodSeconds`)
- Tolerate up to 6 consecutive failures (`failureThreshold`)—equivalent to one
  minute—before marking the container as *not ready*

```yaml
{{< include "yaml/freddie-custom.yaml" >}}
```

This approach is particularly useful when the default settings don’t match your
workload’s characteristics—especially when fine-tuning `failureThreshold`.

As you may have noticed, these settings apply uniformly to all PostgreSQL
instance pods, regardless of whether they are primaries or standbys.

Now, let’s explore the rest of the capabilities—starting with my favourite:
replica-specific configuration.

## Probe Strategies

Readiness probe strategies in CloudNativePG work just like those for startup
probes, with the key difference being when they are executed and the parameter
used: `.spec.probes.readiness.type`. For a detailed explanation of the
different strategies, please refer to the previous article.

To summarise, the default type is `pg_isready`, but you can also choose from
`query` and `streaming`.

For example, the following cluster configuration uses a `query`-based strategy
for both the startup and readiness probes:

```yaml
{{< include "yaml/freddie-query.yaml" >}}
```

The rest of this article focuses on the `streaming` strategy and its impact on
replicas within a CloudNativePG high-availability (HA) cluster.

## Readiness Probes on Replicas

While configuring a readiness probe on a primary is relatively
straightforward—mostly a matter of tuning the right parameters and letting
`pg_isready` do its job—it’s on replicas that CloudNativePG’s Kubernetes-native
approach truly shines.

The key idea we’ve adopted is to extend the concept of *readiness* to also
influence automated promotion decisions. In certain scenarios, you may want the
cluster to remain without a leader temporarily, to preserve data integrity and
prevent a lagging replica from being promoted prematurely.

By setting the probe `type` to `streaming`, a replica is considered *ready*
only if it is actively streaming from the primary. This ensures that only
healthy, up-to-date replicas are eligible for client traffic—and potentially
for promotion.

In more advanced setups, you can further tighten promotion criteria by ensuring
that any replica with non-zero lag—based on the most recent readiness probe—is
excluded from promotion. This behaviour requires synchronous replication to be
enabled. The following manifest demonstrates this configuration:

```yaml
{{< include "yaml/freddie-streaming.yaml" >}}
```

In this example, the readiness probe checks every 10 seconds and allows up to 6
consecutive failures before marking the replica as *not ready*. The
`maximumLag: 0` setting ensures that any replica consistently showing even
minimal lag is excluded from being considered ready.

With synchronous replication enabled as shown above, PostgreSQL requires that
each transaction be acknowledged by at least one standby before a successful
`COMMIT` is returned to the application. Because PostgreSQL treats all eligible
replicas equally when forming the synchronous quorum, even minimal replication
lag can cause readiness probes to *flap*—frequently switching between ready and
not ready states.

For instance, if a replica is located in an availability zone with slightly
higher network latency, it may consistently fall just behind the primary enough
to be marked as *not ready* by the probe.

This can lead to the replica being temporarily removed from read services and
disqualified from promotion. While this behaviour might be acceptable or even
desirable in some cases, it’s important to fully understand and account for the
operational consequences. In any case, be sure to tune these probe settings
carefully according to the specifics of your environment and your tolerance for
lag before you use this setup in production.

## Key Takeaways

By default, readiness probes in CloudNativePG help ensure that PostgreSQL
instances are functioning correctly and ready to serve traffic—writes for
primaries, reads for Hot Standby replicas.

While the default `pg_isready`-based readiness probe is usually sufficient for
primaries, replicas often benefit from stricter checks. As you've seen in this
article, the `streaming` probe type—especially when combined with the
`maximumLag` setting and synchronous replication— provides a powerful mechanism
to enforce tighter consistency guarantees and to prevent *non-ready* replicas
from being promoted. (And yes, I do recommend enabling synchronous replication
in production, even if it comes with a slight performance cost.)

Now, if you're wondering, *“What’s the recommended setup for me?”*—the honest
answer is: *It depends*. I know that’s not the clear-cut advice you might have
hoped for, but there’s no one-size-fits-all solution. The goal of this article
is to equip you with the knowledge and tools to make an informed choice that
best suits your environment and requirements.

At the very least, you now have a rich set of options in CloudNativePG to
design your PostgreSQL cluster’s readiness strategy with precision.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Tanzanian Elephant“](https://commons.wikimedia.org/wiki/File:Tanzanian_Elephant.jpg)._

