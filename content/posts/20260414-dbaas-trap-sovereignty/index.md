---
title: "Owning the pipe: physical replication, cloud neutrality, and the escape from DBaaS lock-in"
date: 2026-04-14T10:32:59+10:00
description: "Why the physical replication stream is the key primitive that DBaaS providers deliberately withhold — and how a cloud-neutral stack built on PostgreSQL, Kubernetes, and CloudNativePG gives it back to you."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "dok", "data on kubernetes", "dbaas", "sovereignty", "wal", "physical-replication", "open-source", "cncf"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_This article examines how managed database services deliberately suppress
access to the physical replication stream, turning operational convenience into
permanent lock-in. It makes the case for a cloud-neutral stack — PostgreSQL,
Kubernetes, and CloudNativePG — as the only architecture that returns full
operational sovereignty to the organisation that owns the data._

<!--more-->

---

Over the past decade, Kubernetes has done something remarkable: it turned
infrastructure into a portable abstraction. Compute workloads can now move
between any cloud, any data centre, and any bare-metal cluster without
rewriting a line of application code. The underlying hardware has been
effectively commoditised.

The database has not.

While every other layer of the stack has been liberated, the data layer has
not. PostgreSQL sits at the centre of this story. As the world's most deployed
open-source relational database, it is also the engine most targeted by
hyperscaler DBaaS offerings — and the one whose most powerful primitive is most
deliberately withheld: the WAL stream, PostgreSQL's physical replication
mechanism.

## The Day 2 reality of managed databases

The appeal of Database-as-a-Service is real. On Day 1, you click a button and a
production-grade PostgreSQL cluster appears. No storage provisioning, no
replication configuration, no backup policy to write. It is genuinely
impressive, and it is easy to understand why organisations reach for it.

Day 2 is where the architecture reveals itself.

High availability, disaster recovery, point-in-time recovery, performance
tuning, major version upgrades — all of this is managed through a proprietary
control plane that your team does not own, cannot inspect, and cannot export.
The operational intelligence that should live in your platform, expressed as
code, reviewed by your engineers, and versioned in your repositories, is instead
locked inside a hyperscaler's console.

This is not merely an inconvenience. When you need to respond to a compliance
requirement, a regulatory change, or a geopolitical shift that demands you move
workloads to a different jurisdiction or cloud, you discover that the
operational steering wheel is not in your hands. The muscle memory required to
operate your database at scale was never yours to begin with.

## The physical replication gap

The most consequential thing a managed database provider withholds is access to
the WAL stream — the physical replication stream that is the beating heart of
PostgreSQL.

Physical replication is what makes it possible to maintain a byte-for-byte
replica of a primary instance in real time. It underpins streaming WAL to
object storage for backup and point-in-time recovery, live standby clusters
across regions, and the kind of frictionless, ongoing portability that makes
cloud neutrality operational rather than aspirational.

The distinction between PostgreSQL's logical tools matters here. Logical backup
and restore — pg_dump — requires a maintenance window proportional to dataset
size, making it impractical at production scale for large databases. Logical
replication is a different matter entirely: operating continuously at the level
of decoded changes, it is well-suited to a controlled, one-time migration out of
a managed service and is the foundation of blue-green major version upgrades.
It is, in fact, the exact mechanism described in the migration section later in
this article. But logical replication is not designed for permanent, ongoing
portability: it does not replicate DDL, sequences, or large objects, and it
cannot sustain the continuous multi-cluster replication that operational
sovereignty requires over the long term.

That sustained capability requires the WAL stream. And managed database
providers deliberately do not expose it. This is not an oversight — it is the
architecture of lock-in. Once your data reaches the scale where ongoing
physical replication matters, and that stream is withheld, the cost of leaving
grows faster than the cost of staying. The provider knows it.

## The cloud-neutral resolution

The solution is not to avoid the cloud. It is to refuse the false choice between
cloud convenience and operational control.

A cloud-neutral PostgreSQL architecture, built on open-source components, gives
you both. The stack is straightforward:

- **Compute:** Kubernetes — the software-defined, portable infrastructure layer
  that runs identically on any cloud or bare-metal environment.
- **Operator:** CloudNativePG — the open-source Kubernetes operator that
  codifies all Day 2 operational tasks declaratively.
- **Engine:** Standard PostgreSQL — unmodified, fully open, with no proprietary
  extensions or behavioural divergence.

What makes this stack significant is not any individual component, but the fact
that the entire configuration lives in your version control system as Kubernetes
manifests. High availability topology, backup schedules, retention policies,
replication configuration, resource limits — all of it is declarative, auditable
and portable. It moves with you.

I explored the broader implications of this approach in a
[post on the CNCF blog](https://www.cncf.io/blog/2024/11/20/cloud-neutral-postgres-databases-with-kubernetes-and-cloudnativepg/),
if you want to go deeper on the cloud-neutrality angle.

## What CloudNativePG actually delivers on Day 2

[CloudNativePG](https://cloudnative-pg.io) was purpose-built for the Day 2
problem. As a CNCF Sandbox project — the first relational database operator to
enter the CNCF since 2018 and the first ever for PostgreSQL — it automates the
full lifecycle of a PostgreSQL cluster on Kubernetes: automated failover,
synchronous replication, point-in-time recovery, rolling updates, major version
upgrades, and more.

Crucially, because CNPG manages standard PostgreSQL with full access to the
engine internals, the physical replication stream is yours. You own the pipe.

You can stream your WAL to object storage for backup and PITR. You can maintain
a physical standby in a separate Kubernetes cluster — in a different region or
a different cloud entirely — using CloudNativePG's
[distributed topology for replica clusters](https://cloudnative-pg.io/docs/current/replica_cluster#distributed-topology).
You can migrate your entire dataset to a new environment by promoting that
standby — with downtime measured in seconds, not hours.

This is the capability that managed services deliberately withhold, and it is
the capability that makes portability permanent rather than theoretical.

## Observability as a first-class concern

Sovereignty over data and compute is necessary but not sufficient. If your
metrics, logs, and traces are trapped in a proprietary cloud console, you lose
operational visibility the moment you move.

CloudNativePG integrates natively with the CNCF observability stack. It
produces [structured JSON logs directly to stdout](https://cloudnative-pg.io/docs/current/logging),
making them immediately consumable by any log aggregation pipeline. It exposes
a rich set of [PostgreSQL metrics via a native Prometheus endpoint](https://cloudnative-pg.io/docs/current/monitoring),
and it supports OpenTelemetry for distributed tracing.

Your "eyes and ears" are as portable as your data. There is no
proprietary dashboard you must replicate or vendor-specific agent you must
re-instrument when you change cloud providers.

## Migrating without a maintenance window

For organisations currently running on a managed database service, the migration
path follows a clear sequence.

First, build a parallel environment. Use
[logical replication](https://cloudnative-pg.io/docs/current/logical_replication)
to synchronise your data from the managed service into a CNPG-managed cluster. This phase can run
indefinitely alongside production — it is low-risk, reversible, and gives your
team the operational experience of running the new platform under real load
before it matters.

Second, perform the cutover. Because the data is continuously synchronised,
the cutover is a controlled pivot rather than a disruptive migration. Downtime
is a function of the replication lag at the moment you flip, not of dataset
size.

Third, maintain permanent portability. Once you are within the CloudNativePG
ecosystem and running standard PostgreSQL with full WAL access, you can replicate
your cluster anywhere — different cloud, different region, bare metal — using
native physical replication. The investment in moving is a one-time cost. The
freedom it buys is permanent.

The financial services sector illustrates this well. At KubeCon Amsterdam, Laurent Parodi and I gave a
[talk](https://www.youtube.com/watch?v=m0LBKjlxrog) in which he walked through
how HSBC approached this migration, navigating the intersection of strict
regulatory requirements and the operational scale you would expect from one of
the world's largest financial institutions. It is one of the more instructive
real-world examples of this architecture in a heavily regulated environment.

## Staying in the cloud, leaving the DBaaS

For many organisations, the most immediate path forward does not require moving
away from the cloud at all. If your applications already run on a
hyperscaler-managed Kubernetes service — Amazon EKS, Azure Kubernetes Service,
Google GKE — you are already closer to the solution than you might think.

The logical first step is not to migrate to a different provider or to bare
metal. It is to move the PostgreSQL database from the hyperscaler's DBaaS
offering — Amazon RDS, Azure Database for PostgreSQL Flexible Server — into the
Kubernetes cluster you already operate, colocated with the applications that
connect to it. CloudNativePG runs identically on EKS or AKS as it does on any
other conformant Kubernetes distribution. Your application manifests do not
change. Your network topology typically improves, since the database is now
inside the same cluster rather than accessed over a managed service endpoint.

The outcome is immediate and compounding: you recover the operational
intelligence currently locked inside RDS or Flexible Server, you eliminate the
DBaaS premium from your cloud bill, and — crucially — you regain access to the
WAL stream. From that point, replicating to a second region, streaming WAL to
object storage, or moving to a different environment entirely are all decisions
you make on your own terms, at a time of your choosing.

For a step-by-step walkthrough of this migration — covering Amazon RDS, Azure
Database for PostgreSQL Flexible Server, and Google Cloud SQL as source systems
— I wrote
[CloudNativePG Recipe 5]({{< relref "../20240327-zero-cutover-migrations/index.md" >}}),
which covers the full logical replication setup for a near-zero-downtime
cutover into Kubernetes. Some operational details will have evolved with newer
releases, but the approach and the underlying mechanics remain sound.

If you are running on Azure AKS specifically, this [walkthrough on deploying
CloudNativePG on AKS](https://www.youtube.com/watch?v=KEApG5twaA4) is a good
companion. The same logic applies across all hyperscaler Kubernetes offerings:
Today, the cloud is not the problem. The DBaaS is.

## Compliance is now a pull force

For organisations operating under the EU Data Act or preparing for the Cyber
Resilience Act, operational sovereignty is no longer purely an architectural
preference — it is a compliance requirement. Both frameworks demand demonstrable
data portability and the ability to move critical workloads between providers or
onto private infrastructure.

A cloud-neutral architecture built on open standards is the most direct path to
satisfying these requirements, and the architecture described here is precisely
what auditors and regulators mean when they ask for evidence of portability. It
is also the architecture that gives you the operational capability to actually
execute a migration under time pressure, rather than just asserting in a
compliance document that you could.

## The bottom line

DBaaS lock-in is not inevitable. It is the product of a specific architectural
choice — handing Day 2 operational responsibility to a managed service that
withholds the one primitive that makes portability possible at scale.

The alternative is not to build everything yourself. CloudNativePG handles the
hard operational problems. Kubernetes handles infrastructure portability. Standard
PostgreSQL handles your data, with no proprietary divergence. The stack is mature,
production-proven, and already running mission-critical workloads at organisations
including IBM, Google Cloud, Microsoft Azure, HSBC, Tesla, GEICO Tech and Novo
Nordisk. The [full adopters list](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md)
is publicly maintained and growing.

Owning the pipe — keeping access to the physical replication stream — is the
difference between a database that can follow your organisation wherever it needs
to go, and one that cannot.

That distinction is worth building for.

---

If you are interested in the practicalities of running this stack in production,
I encourage you to explore the [CloudNativePG documentation](https://cloudnative-pg.io/docs/)
and [get in touch with the community](https://github.com/cloudnative-pg#getting-in-touch).
The project is open, governed transparently under the CNCF, and built to remain
so.

The themes in this article also formed the basis of a talk I gave with Floor
Drees at [Open Sovereign Cloud Day, KubeCon EU 2026](https://colocatedeventseu2026.sched.com/event/2H5Uc/beyond-the-dbaas-trap-achieving-data-sovereignty-with-kubernetes-and-cloudnativepg-floor-drees-gabriele-bartolini-edb)
— titled "Beyond the DBaaS Trap: Achieving Data Sovereignty with Kubernetes
and CloudNativePG". If you prefer the spoken version, that is a good
companion to this article.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_This article was drafted and refined with the assistance of Claude (Anthropic).
All technical content, corrections and editorial direction are the author's own._
