---
title: "CNPG Recipe 21 – Finer Control of Postgres Clusters with Liveness Probes"
date: 2025-08-15T00:03:25+10:00
description: "how CloudNativePG leverages Kubernetes liveness probes to give users more reliable and configurable control over PostgreSQL in high-availability clusters"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "probes", "cncf", "startup", "pg_isready", "liveness", "isolation", "primary isolation", "split-brain"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In this article, I explore how CloudNativePG 1.27 enhances PostgreSQL
liveness probes, including primary isolation checks that mitigate split-brain
scenarios and integrate seamlessly with Kubernetes. We also discuss how these
improvements lay the groundwork for advanced features like quorum-based
failover while maintaining stability, safety, and community-driven
decision-making._

<!--more-->

---

In the previous articles —
[CNPG Recipe 19 - Finer Control Over Postgres Startup with Probes]({{< relref "../20250617-startup-probes/index.md" >}})
and [CNPG Recipe 20 - Finer Control of Postgres Clusters with Readiness Probes]({{< relref "../20250625-readiness-probes/index.md" >}})
— I covered the enhancements to the
[probing infrastructure introduced in CloudNativePG 1.26](https://github.com/cloudnative-pg/cloudnative-pg/pull/6623),
focusing on startup and readiness probes respectively.

In this article, I'll explore the third — and last — probe provided by CloudNativePG: the **liveness** probe.

---

## Understanding Liveness Probes

[Liveness probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/#liveness-probe)
have been part of Kubernetes since the very beginning. Their purpose is to
ensure that a workload — in our case, PostgreSQL — is still running and able to
perform its intended function.

Just like the readiness probe, the liveness probe only starts running *after*
the startup probe has succeeded. It then continues to run periodically for the
entire lifetime of the container.

As mentioned in CNPG Recipe 19, liveness probes share the same configuration
parameters as startup and readiness probes:

* `failureThreshold`
* `periodSeconds`
* `successThreshold`
* `timeoutSeconds`

---

## How CloudNativePG Implements Liveness Probes

At a high level, the goal of the liveness probe is to confirm that the
PostgreSQL workload is healthy. As long as the probe succeeds, the Kubernetes
**kubelet** will keep the pod running. If the probe fails, the kubelet will
restart the pod.

From CloudNativePG’s perspective, the liveness probe checks whether the
**instance manager** is functioning. If you’re not familiar with it, the
instance manager is the entrypoint (`PID 1`) of the `postgres` container — the
main workload. I often describe it as a distributed extension of the operator’s
brain, or more playfully, its *right arm*.

The instance manager provides, among other things, a REST API used by the
operator to coordinate operations. This includes controlling the PostgreSQL
server process itself and serving the endpoints for the startup, readiness, and
liveness probes.

By default, the liveness probe reports **success** as long as the instance
manager is up and running. It reports **failure** if it cannot be reached for
more than `.spec.livenessProbeTimeout` seconds (default: 30 seconds).

Starting with CloudNativePG 1.27, this basic check is enhanced on the
primary instance with an additional safeguard: it now verifies whether the
instance is isolated from both the API server and the other replicas. I’ll
cover the details of this improvement later in the article.

The `.spec.livenessProbeTimeout` setting acts as a higher-level abstraction
over the raw Kubernetes probe configuration. Internally, it maps to the
following parameters:

```yaml
failureThreshold: FAILURE_THRESHOLD
periodSeconds: 10
successThreshold: 1
timeoutSeconds: 5
```

Here, `FAILURE_THRESHOLD` is automatically calculated as:

```
FAILURE_THRESHOLD = livenessProbeTimeout / periodSeconds
```

This means that with the default values (`livenessProbeTimeout: 30`,
`periodSeconds: 10`), `FAILURE_THRESHOLD` will be `3`.

## Full Probe Customisation

Just like with readiness probes, if your scenario requires finer control, you
can customise the liveness probe through the `.spec.probes.liveness` stanza by
defining the standard Kubernetes probe parameters you should already be
familiar with.

The following example configures Kubernetes to:

- Probe the container every 5 seconds (`periodSeconds`)
- Allow up to 6 consecutive failures (`failureThreshold`) — still
  equivalent to a 30-second tolerance window, but with a higher probing
  frequency — before marking the container as *not alive*

```yaml
{{< include "yaml/freddie-custom.yaml" >}}
```

## Liveness Probe and Primary Isolation

A few months ago, an
[issue](https://github.com/cloudnative-pg/cloudnative-pg/issues/7407) was
raised in CloudNativePG regarding the risk of a split-brain scenario during a
network partition. This sparked a productive
[discussion](https://github.com/cloudnative-pg/cloudnative-pg/issues/7407)
within the community, which I recommend reading.
It ultimately led to a [new default behaviour](https://cloudnative-pg.io/documentation/current/instance_manager/#primary-isolation)
introduced in CloudNativePG 1.27, after debuting as an
[experimental feature in 1.26](https://cloudnative-pg.io/documentation/1.26/instance_manager/#primary-isolation-alpha).

The enhancement applies specifically to the liveness probe on **primary** pods.
In addition to checking that the instance manager is running, the probe now
also verifies that the primary can:

- Reach the Kubernetes API server
- Reach the instance manager of every replica, via their REST API endpoint

If either check fails for longer than the configured `livenessProbeTimeout`,
the kubelet restarts the pod. On restart, the instance manager first attempts
to download the Cluster definition. If this fails — for example, because the
pod is still isolated — PostgreSQL will not start. This ensures that an
isolated primary cannot continue accepting writes, reducing the risk of data
divergence.

While this does not completely prevent split-brain — the isolated primary can
still accept writes from workloads in the same partition until the pod is
terminated — it helps mitigate the risk by shortening the time window during
which two primaries might be active in the cluster (by default, 30 seconds).

This behaviour is conceptually similar to the
[failsafe mode in Patroni](https://patroni.readthedocs.io/en/latest/dcs_failsafe_mode.html).
The key difference is that CloudNativePG provides its own built-in mechanism,
fully integrated with the Kubernetes liveness probe.

As mentioned earlier, the primary isolation check is enabled by default on
every PostgreSQL cluster you deploy. While there is generally no reason to
disable it, you can turn it off if needed, as shown in the example below:


```yaml
{{< include "yaml/freddie-disable-check.yaml" >}}
```

## Key Takeaways

CloudNativePG’s probing infrastructure has matured into a robust,
Kubernetes-native system that now accounts for both replicas and primaries. The
primary isolation check in the liveness probe enhances cluster reliability by
reducing the risk of unsafe operations in network-partitioned scenarios, making
PostgreSQL behaviour more predictable and safer for administrators.

Key practical takeaways:

- **Primary isolation check enabled by default:** Liveness probes now verify
  that a primary can reach the API server and other replicas.
- **Mitigates split-brain scenarios:** Reduces the time window during which
  multiple primaries could accept writes. When synchronous replication is used
  (as recommended), the likelihood of a split-brain on an isolated primary is
  close to zero.
- **Fully integrated with Kubernetes probes:** Achieves robust behaviour
  without introducing external dependencies.
- **Foundation for quorum-based failover:** Enables the experimental
  [quorum-based failover](https://cloudnative-pg.io/documentation/current/failover/#failover-quorum-quorum-based-failover)
  feature in 1.27, which will be stable in 1.28, offering safer synchronous
  replication failover.

This evolution reflects a careful, staged approach: first reorganising startup
and readiness probes, then adding primary isolation checks, and finally paving
the way for advanced failover mechanisms—demonstrating CloudNativePG’s
commitment to stability, safety, and innovation, and ensuring that the project
and its community were mature enough to make these decisions together.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephants are smart, big, and sensitive“](https://commons.wikimedia.org/wiki/File:Elephants_are_smart,_big,_and_sensitive.jpg)._

