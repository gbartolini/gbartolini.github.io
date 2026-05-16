---
title: "CloudNativePG and Crunchy PGO: an honest, opinionated comparison"
date: 2026-05-16T09:00:00+10:00
description: "A personal comparison of CloudNativePG and Crunchy PGO, covering architecture, image design, backup, upgrades, observability, licensing and community health."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg",
  "dok", "data on kubernetes", "crunchy", "pgo", "operator", "comparison",
  "high-availability", "backup", "migration", "patroni", "security", "openssf",
  "governance", "cncf", "observability", "logging", "logical-replication"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_Since Crunchy Data was acquired by Snowflake, the comparison question has
followed me everywhere. As a co-founder and daily maintainer of CloudNativePG, I
am the wrong person to ask for neutrality, and I will not pretend otherwise.
What I can offer is honest bias, which I find more useful than performed
objectivity. What follows acknowledges what Crunchy built before most engineers
took running PostgreSQL on Kubernetes seriously, examines the architectural
decisions that separate the two operators, and presents the community data
without excessive editorialising. The conclusion will not surprise anyone who
knows me._

<!--more-->

---

Since
[Crunchy Data was acquired by Snowflake](https://www.snowflake.com/en/news/press-releases/snowflake-acquires-crunchy-data-to-bring-enterprise-ready-postgres-offering-to-the-ai-data-cloud/),
I have been asked with increasing frequency how CloudNativePG compares to
Crunchy PGO. I wrote
[Recipe 24]({{< relref "../20260513-crunchy-to-cloudnativepg-pg18/index.md" >}})
to answer the practical question of how to migrate. This post attempts something
harder: an honest assessment of why the two operators differ and what those
differences mean for teams choosing a long-term platform for PostgreSQL on
Kubernetes.

I will acknowledge Crunchy's legacy, explain the architectural choices that I
believe make CloudNativePG the stronger foundation, point to data where it
exists, and flag the areas where my view is unavoidably subjective. I will not
pretend this is a neutral document.

## Crunchy's pioneering role

Crunchy Data released the first PostgreSQL operator for Kubernetes in March
2017, less than two years after Kubernetes itself debuted and shortly after
CoreOS introduced the operator pattern. That was genuinely ahead of its time. My
team at 2ndQuadrant (later acquired by EDB) monitored the ecosystem closely
during this period but chose to wait, primarily due to the immaturity of
Kubernetes storage primitives. The pivotal moment came in April 2019, when
Kubernetes 1.14 introduced stable support for local persistent volumes. Our
first cloud-native operator, Cloud Native BDR, followed shortly after, built for
active/active workloads using 2ndQuadrant's bi-directional replication
technology (now EDB Postgres Distributed). The
[first commit](https://github.com/cloudnative-pg/cloudnative-pg/commit/f036736296cd44fc5911479ca9f4b3ac76ee12ca)
to what became CloudNativePG was made on 18 February 2020, by Leonardo Cecchi,
Marco Nenciarini and myself.

The point is not to minimise what Crunchy built. PGO ran production PostgreSQL
on Kubernetes before most people thought that was a reasonable idea, and a large
number of teams built their infrastructure on it. That record deserves
acknowledgement before any comparison.

## The architectural divide

The most important difference between the two operators is not a feature. It is
a philosophy about where the intelligence for managing PostgreSQL high
availability should live.

Crunchy PGO delegates HA to [Patroni](https://patroni.readthedocs.io/), a
Python-based distributed HA manager that runs as a process inside each pod.
Patroni is a well-respected project and, in my view, the state of the art for
PostgreSQL cluster management on traditional Linux environments. That is
precisely the point: it was designed for a world without Kubernetes, and using
it inside a Kubernetes pod means running a sophisticated distributed system
inside another sophisticated distributed system. Patroni coordinates failover
through a distributed configuration store, which can be etcd, Consul, ZooKeeper
or Kubernetes itself, and PGO's role is primarily to provision and configure
what Patroni needs. The operator wraps Patroni rather than replacing it.

At KubeCon Salt Lake City in 2024,
[an engineer from Crunchy explained their reasoning directly](https://youtu.be/p2v7bPJkrVU?si=oBhPhAPDlfI1G4ec&t=152):
why write complex distributed systems code from scratch when Patroni already
existed and was battle-tested? It is a reasonable position, and I understand it.
Our team simply reached a different conclusion. We took a fundamentally
different decision: to trust the Kubernetes API for exactly what it was designed
for (managing distributed systems and applications) and to write the HA logic
natively in the operator rather than delegating it to a separate tool.

CloudNativePG was designed roughly three years later, with that premise at its
core: Kubernetes is the control plane, and the operator should exploit it
directly. There is no Patroni, no etcd dependency for HA and no HA framework
running in parallel with Kubernetes. The Kubernetes API server is the single
source of truth for the state of every resource, including the primary/standby
topology. The
[controller documentation](https://cloudnative-pg.io/docs/current/controller)
and the
[technical architecture document](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/contribute/technical-architecture.md)
describe what that looks like in practice.

## Direct Pod management

CloudNativePG does not use `StatefulSets`. It manages `Pod` and `PVC` resources
directly, which gives the operator granular control that StatefulSets cannot
provide. When a failover occurs, CloudNativePG promotes the replica with the
highest Log Sequence Number (LSN), ensuring the most up-to-date instance becomes
the new primary regardless of its name or index. StatefulSet-bound ordinal logic
cannot express that kind of decision natively; it requires a separate
coordination layer, which is exactly what Patroni provides in PGO's case.

Direct Pod management also enables CloudNativePG to coordinate updates to
sensitive PostgreSQL parameters (those that must be equal to or greater on a
standby than on the primary, such as `max_connections` and `max_wal_senders`) in
the correct order across the cluster. With StatefulSets, that kind of
coordinated sequencing requires logic on top of the primitive.

## The Instance Manager

There are no HA management sidecars in CloudNativePG. The management logic runs
as an Instance Manager, a Go binary that acts as PID 1 inside the PostgreSQL
container. It handles the full Postgres lifecycle, participates in self-healing
and communicates directly with the Kubernetes API to report health, replication
lag and LSN.

The probes it exposes to Kubelet are database-aware rather than generic. The
startup probe prevents Kubelet from restarting the pod during `initdb`, recovery
or WAL replay. The readiness probe validates `pg_isready` on the primary and,
when configured, checks replication lag on replicas before allowing traffic. The
liveness probe on the primary performs an isolation check: if both the API
server and peer instances become simultaneously unreachable, the probe
deliberately fails, causing Kubelet to restart the pod after 30 seconds
(configurable). This mitigates the risk of data loss caused by a possible
split-brain by taking the isolated primary offline. It is worth noting that
Patroni introduced a similar capability in
[version 3.0.0](https://github.com/patroni/patroni/blob/master/docs/releases.rst#version-300)
through its [DCS failsafe mode](https://github.com/patroni/patroni/pull/2379).
CloudNativePG independently implemented the same concept the Kubernetes way:
rather than querying peers over a REST API, it lets the liveness probe and
Kubelet do the work. The discussion that led to our implementation is
[here](https://github.com/cloudnative-pg/cloudnative-pg/discussions/7462). It is
a good example of how the same problem can be solved with fundamentally
different primitives depending on your execution environment.

## On Kubernetes API server availability

A common objection to this architecture is: what happens during a Kubernetes API
server outage? CloudNativePG's answer is to suspend failover operations and
prioritise data protection. But I think this question deserves a frank response
rather than purely a technical one.

If your Kubernetes API server is unavailable, your entire cluster is
experiencing a major incident. Every application running on it is affected, not
just PostgreSQL. Deciding which database instance to promote is not your most
urgent problem in that scenario. Introducing a parallel HA system to handle that
decision during a cluster-wide outage is solving the wrong problem at the wrong
layer. The correct response is a resilient multi-region architecture, which
CloudNativePG supports through its
[distributed topology](https://cloudnative-pg.io/docs/current/replica_cluster#distributed-topology)
for replica clusters.

The practical consequence of this approach is a much smaller operational
surface. You do not need to understand Patroni to operate CloudNativePG. There
is no additional distributed system to monitor, debug or upgrade alongside the
operator. Failures have fewer places to hide.

## Image design, footprint and security

The architectural choice to embed nothing but PostgreSQL in the operand image
has direct consequences for image size and security posture. Crunchy's operand
image bundles Patroni, pgBackRest, pgAudit, pgvector, TimescaleDB, pg_cron,
pg_partman and other extensions into a single UBI9-based image, because they all
need to be co-located for Patroni to function. CloudNativePG's minimal image
contains only PostgreSQL, with extensions delivered at runtime as OCI image
volumes via the Kubernetes `ImageVolume` feature (requires PostgreSQL 18 or
later and Kubernetes 1.35 or later, where `ImageVolume` is enabled by default;
it can be enabled via feature gate on 1.33 and 1.34), covered in detail in
[CNPG Recipe 23]({{< relref "../20251201-extensions/index.md" >}}). Adding or
removing an extension is a declarative change to the `Cluster` manifest; it does
not require a different base image.

The numbers are from `docker scout quickview` against current images:

| Image | Packages | Critical | High |
|---|---|---|---|
| `crunchy-postgres:ubi9-17.9-2610` | 625 | 2 | 156 |
| `postgresql:18-minimal-trixie` | 140 | 0 | 4 |

The CNPG minimal-trixie image carries 140 packages against 625 for the Crunchy
source image, zero critical vulnerabilities against two and four high against
156. Its Debian Trixie Slim base has zero known vulnerabilities of its own. The
package count matters operationally: fewer packages means a smaller blast radius
for any future disclosure and a shorter list to audit. The CNPG minimal image
also ships with a full SBOM provenance attestation.

On the topic of image licensing: Crunchy Data's container images have
historically been distributed under the
[Crunchy Data Developer Program](https://www.crunchydata.com/developers/terms-of-use),
which restricts production use for organisations with more than 50 employees.
The operator itself is open-source; the images it uses by default have not
always been. This is a distinction that organisations often discover later than
they should. Whether this has changed following the Snowflake acquisition is
something to verify directly with Crunchy before making a procurement decision.
Every image in the CloudNativePG ecosystem — operator, operand, extension images
— is fully open-source under the Apache License 2.0.

## Major version upgrades

This is an area where CloudNativePG has invested heavily and where the
difference is concrete.

Crunchy PGO v6 provides major version upgrades through a declarative
`PostgresCluster` spec change, executed via an imperative reconciliation loop.
The process requires a maintenance window proportional to dataset size and
offers limited rollback options.

As I showed in
[Recipe 24]({{< relref "../20260513-crunchy-to-cloudnativepg-pg18/index.md" >}}),
CloudNativePG offers two paths. The offline path uses `pg_dump` / `pg_restore`
via the built-in `bootstrap.initdb.import` mechanism, fully declarative,
executed at cluster bootstrap. The online path uses native PostgreSQL logical
replication with declarative `Publication` and `Subscription` resources,
reducing the cutover window to seconds regardless of dataset size. A third path,
in-place major upgrades via `pg_upgrade`, was introduced in
[CNPG Recipe 17]({{< relref "../20250403-major-inplace-upgrades/index.md" >}})
and supports automated rollback when replicas are present. All three paths are
available today.

## Backup and recovery

Our involvement in PostgreSQL backup significantly predates CloudNativePG.
[Barman](https://pgbarman.org/) originated in the 2ndQuadrant team and is one of
the most widely used tools for physical PostgreSQL backup and WAL archiving.
That experience shaped how we approached backup in CloudNativePG from the start.

Crunchy PGO embeds pgBackRest in the operand image and configures it through the
`PostgresCluster` spec. pgBackRest is an excellent tool. The consequence of the
embedded model is that backup code and database code are coupled: a pgBackRest
update requires a new operand image.

CloudNativePG supports two backup approaches,
[compared in detail in the documentation](https://cloudnative-pg.io/docs/current/backup#comparison-summary).
The first is Kubernetes-native volume snapshots, the only backup method handled
directly by the operator itself. Volume snapshots support both cold and hot
backups, though hot backups require the WAL archive to be in place for a
consistent restore. At
[KubeCon Atlanta 2023](https://www.youtube.com/watch?v=WGQq4MWzW6E), we
demonstrated a 2-minute recovery of a 4.5 TB database using this approach.

The second is the plugin interface (
[CNPG-I](https://github.com/cloudnative-pg/cnpg-i)), which decouples backup
tooling from the operator entirely. The Barman Cloud Plugin is the reference
implementation and the only one currently maintained by the community, but the
interface is open: nothing prevents the community or organisations from writing
plugins for other tools such as pgBackRest or WAL-G.

## Observability

Both operators provide PostgreSQL metrics for Prometheus. CloudNativePG goes
further by supporting declarative custom metrics defined in ConfigMaps or
Secrets and referenced by the `Cluster` resource, allowing teams to manage
application-specific queries as Kubernetes resources alongside the cluster
itself. The
[monitoring documentation](https://cloudnative-pg.io/docs/current/monitoring/)
and the community-maintained Grafana dashboard cover the full default metric
set.

On the logging side, every container managed by CloudNativePG writes structured
logs to stdout in JSON format, as documented in the
[logging documentation](https://cloudnative-pg.io/docs/current/logging). This is
a deliberate design choice: it requires no log file management inside the pod
and integrates directly with any Kubernetes-level log aggregation solution,
whether that is the EFK stack, Loki, a cloud provider's native offering or a
dedicated operator such as the [Logging operator](https://kube-logging.dev/).

## Community health and governance

This is the section where I have the most obvious conflict of interest, so I
will let the data speak rather than editorialise.

The table below covers signals measured over the 18 months to May 2026.

| Signal | PGO (CrunchyData) | CloudNativePG |
|---|---|---|
| GitHub stars (main repo) | 4.4k | 8.6k (~10k across org) |
| Total commits | 4,418 | 4,662 (newer project) |
| Commit rate (all-time avg) | ~480/year | ~745/year |
| Commit rate (last 3 years) | ~235/year | ~894/year |
| Open pull requests | ~18 | ~174 |
| Contributors | vendor-internal | 200+ from multiple orgs |
| GA releases (last 18 months) | ~4 (current branch) | ~18 (consistent cadence) |
| Longest release gap (last 18 months) | 8 months (Mar–Nov 2025) | no gaps (6–8 week cadence) |
| Public governance | none | [CNCF (GOVERNANCE.md, MAINTAINERS.md)](https://github.com/cloudnative-pg/governance) |
| CNCF membership | none | Sandbox, incubation pending |
| Public roadmap | none | [ROADMAP.md](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ROADMAP.md) |
| OpenSSF Best Practices Baseline | none | [yes](https://www.bestpractices.dev/en/projects/9933/baseline-2) |
| SECURITY-INSIGHTS.yml | none | [yes](https://github.com/cloudnative-pg/governance/blob/main/SECURITY-INSIGHTS.yml) |
| Threat assessment | none | [yes](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/.github/threat-assessment.yaml) |
| ADOPTERS.md | none | [yes](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md) |
| Documentation | proprietary portal | fully open |

The 8-month gap in PGO's release history (March to November 2025) is a concrete
signal of the slow development and release pace that has characterised the
project recently. The combination of that pace, the Snowflake acquisition and
the absence of public governance is what teams are actually reacting to when
they ask me about their options.

I will also be candid about the CloudNativePG side of the table. 174 open pull
requests is a high number, and it reflects a genuine challenge: the project is
growing faster than our current capacity to review and merge. Part of this
growth is attributable to the rise of AI-generated contributions — a pattern we
have observed across the open-source ecosystem. Our
[AI policy](https://github.com/cloudnative-pg/governance/blob/main/AI_POLICY.md)
is explicit: the human contributor bears full responsibility for everything they
submit, maintainers may close low-effort AI-generated PRs without detailed
critique and we value one carefully considered contribution over ten superficial
ones. Beyond that, we are in a transition phase, actively reducing technical
debt across three areas that are consuming most of our cognitive budget right
now: extension image support (where the work is almost complete), the migration
from the in-core Barman Cloud integration to the plugin model (also nearing
completion) and the refactoring of the end-to-end test suite to work with CNPG-I
plugins. Once these tracks land, the review surface narrows considerably and the
backlog should follow.

CloudNativePG is a [CNCF Sandbox project](https://www.cncf.io/), currently in
the queue for incubation, with health metrics publicly visible on the
[LFX Insights dashboard](https://insights.linuxfoundation.org/project/cloudnativepg).
The main repository has 8.6k stars; across all repositories in the CloudNativePG
GitHub organisation, the total reaches nearly 10,000. The majority of the
development is still driven by EDB, which is entirely expected at this stage of
CNCF maturity. Incubation is the project's next milestone, and the primary
requirement is demonstrating broad production adoption — something I am not
worried about, given the depth of the
[ADOPTERS.md](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md)
file and talks like
[the one I gave at KubeCon with Laurent Parodi from HSBC](https://www.youtube.com/watch?v=m0LBKjlxrog).
Graduation, the third step, is where multi-organisation contribution becomes a
formal criterion, and that is the work ahead once we reach Incubation
(hopefully). The governance model, roadmap and security policy are all public.
Adopters include IBM, Google Cloud, Microsoft Azure, Tesla, GEICO Tech, Novo
Nordisk and Mirakl (8 TB, 300+ clusters), among others listed in
[ADOPTERS.md](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md).

Security transparency has also been a deliberate focus. The
[Open Source Security Foundation (OpenSSF)](https://openssf.org/) has been a key
partner in this work. CloudNativePG complies with the
[OpenSSF Best Practices Baseline](https://www.bestpractices.dev/en/projects/9933/baseline-2),
and at the
[OpenSSF Security Slam 2026](https://openssf.org/blog/2026/04/10/security-slam-2026-celebrating-our-security-champions-and-project-milestones/),
held at KubeCon + CloudNativeCon Europe 2026 in Amsterdam, CloudNativePG was one
of only two projects to earn all five available badges (Cleaner, Chronicler,
Inspector, Mechanizer and Defender). The work produced a
[SECURITY-INSIGHTS.yml](https://github.com/cloudnative-pg/governance/blob/main/SECURITY-INSIGHTS.yml)
file and a
[Gemara threat assessment](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/.github/threat-assessment.yaml)
for the project, among other outcomes. Both are directly relevant to
organisations operating under or preparing for the
[EU Cyber Resilience Act](https://openssf.org/public-policy/eu-cyber-resilience-act/),
which requires software manufacturers to demonstrate security due diligence
throughout the product lifecycle. Having these artefacts in place as an
open-source community project is not a given, and it reflects the kind of
long-term thinking that goes into how CloudNativePG is maintained.

## My honest conclusion

Crunchy Data was a pioneer and built something real. I have genuine respect for
that. But the landscape in 2026 looks different from 2017: Kubernetes is a
mature control plane, the operator pattern is well understood and the cost of
running a parallel distributed system (Patroni) inside your database pods is no
longer justified by the benefits it provides. CloudNativePG was designed from
the start to exploit what Kubernetes actually offers, and that decision shows in
everything from the architecture to the image footprint to the backup model.

If you are evaluating PostgreSQL operators today and your primary concern is
long-term architectural soundness, open governance and a community that is
gaining momentum rather than losing it, the evidence points clearly in one
direction. That is my opinion, and I hold it knowing it is not neutral. It
cannot be, coming from a maintainer and founder of the project (had we not
thought it differently from the start, there would be no CloudNativePG now).

Ultimately, the choice is yours. My honest advice, bias acknowledged, is to try
both and decide what fits your team, your workload and your organisation best.
That is how good engineering decisions get made.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your network
on social media using the provided links below. Your support is immensely
appreciated!

_This article was drafted and refined with the assistance of Claude (Anthropic).
All technical content, corrections and editorial direction are the author's
own._
