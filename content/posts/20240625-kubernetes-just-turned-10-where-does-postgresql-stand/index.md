---
title: "Kubernetes Just Turned Ten: Where Does PostgreSQL Stand?"
date: 2024-06-25T15:46:09+02:00
description: ""
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "dok", "data on kubernetes", "CNPG", "DBa", "CIO", "CNCF", "vm", "DBaaS"]
cover: cover.png
thumb: thumb.png
draft: false
---

_As Kubernetes marks its tenth anniversary, its influence on infrastructure
management continues to grow. This article examines the increasing adoption of
PostgreSQL within Kubernetes, fueled by its extensibility and AI applications.
It highlights the journey of integrating PostgreSQL with Kubernetes, focusing
on the CloudNativePG operator. A comparison between Kubernetes and traditional
VM deployments underscores the advantages for database workloads. The article
also calls for greater awareness and expertise in combining PostgreSQL with
Kubernetes, aiming to enhance the adoption of this fully open-source stack
across the IT landscape._

<!--more-->

---

As [Kubernetes celebrates its tenth anniversary](https://events.linuxfoundation.org/kuber10es-birthday-bash/),
its momentum shows no signs of slowing down. Organisations worldwide are
increasingly migrating their infrastructure to Kubernetes, drawn by its ability
to provide a standardised interface for managing entire data centres and cloud
regions using Infrastructure as Code (IaC). This standardised and portable
infrastructure layer supports private, public, hybrid, and multi-cloud
scenarios, helping organisations mitigate the risk of vendor lock-in from cloud
service providers.

So, where does PostgreSQL adoption in Kubernetes stand as Kubernetes enters its
second decade?


## The Rise of Database Workloads on Kubernetes

Database workloads have recently emerged as a critical use case for Kubernetes,
with the surge in AI applications accelerating this trend. PostgreSQL's
extensibility, complemented by powerful extensions like pgvector, has
significantly boosted the adoption of this robust open-source database.
Phrases like "_[PostgreSQL for everything](https://www.timescale.com/blog/postgres-for-everything/)_"
(Timescale) and "_[Just use Postgres](https://techcrunch.com/sponsor/enterprise-db/edbs-next-move-from-a-postgres-database-company-to-a-postgres-data-ai-platform-company/)_"
(EDB), to cite a few, have gone viral on social media, reflecting the growing
enthusiasm and contributing to [PostgreSQL being recognised as the database of the year in 2023](https://db-engines.com/en/blog_post/106).
I also want to reiterate the [words of PostgreSQL’s Simon Riggs from his visionary keynote speech at PGConf Europe in December 2023](https://www.youtube.com/watch?v=8W-J36IxYv4&ab_channel=PostgreSQLEurope):

> Most, if not all, database use cases can be met by Postgres (plus Extensions).

This article offers my perspective on this significant moment, reflecting on my
5-year journey since initiating PostgreSQL on Kubernetes in 2019 when at
2ndQuadrant, eventually leading to my involvement with
[CloudNativePG](https://cloudnative-pg.io/), the [CNCF](https://www.cncf.io/),
and the [Data on Kubernetes](https://dok.community/) communities.

I will briefly introduce Kubernetes and Cloud Native principles, highlighting
their distinctions from traditional VM-based deployments, especially in the
context of stateless applications. I will then delve into the unique
considerations and challenges associated with stateful workloads such as
Postgres databases.

## Primer: Kubernetes and Cloud Native

Kubernetes provides a standard interface for managing infrastructure but
doesn't stop there. This same interface allows organisations to control the
scheduling and running of containerised applications based on their resource
requirements, such as computing power and storage. Consequently, the physical
location of deployment becomes irrelevant, leading to the common (and somewhat
harsh) analogy in the literature of treating containers like "_cattle_" instead
of "_pets_."

A Kubernetes cluster comprises a control plane and several worker nodes where
applications run. These nodes are typically distributed across different data
centres, also known as availability zones, creating a stretched cluster that
manages the infrastructure and applications across an entire cloud region.

Kubernetes offers many standard resources to help manage the lifecycle of
stateless applications. Three noteworthy examples are:

- **[Pod Resource](https://kubernetes.io/docs/concepts/workloads/pods/)**: This
  is the smallest unit of work in Kubernetes. It typically runs a single
container and is configured with a specific set of resources.
- **[Deployment Resource](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/):**
  This lets you specify how many replicas of an application you want to run
  simultaneously. Kubernetes ensures that the desired number of replicas (pods)
  is maintained at all times through self-healing, high availability, and rolling
  updates.
- **[Service Resource](https://kubernetes.io/docs/concepts/services-networking/service/):**
  By directly cooperating with the Deployment and Pod resources, services ensure
  a stable network identity with your applications, both within Kubernetes and
  externally.

[Kubernetes](https://kubernetes.io/) is also part of a thriving ecosystem of
open-source and openly governed projects built around the
[Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/)
(part of the Linux Foundation). By integrating your infrastructure and applications with
[existing projects](https://landscape.cncf.io/), you can benefit in several
areas, such as:

- **Observability:** Prometheus, OpenTelemetry, Fluentd
- **CI/CD:** Argo, Flux
- **Security:** cert-manager, Istio, Falco, Open Policy Agent

The CNCF has also promoted standard initiatives like the
[Open Container Initiative (OCI)](https://opencontainers.org/)
and, most importantly in our case, the
[Container Storage Interface (CSI)](https://github.com/container-storage-interface/spec/blob/master/spec.md),
which provides a standard layer between Kubernetes and storage communications.

The database area, in particular, has seen significant improvements in the last
few years, with a recent boost driven by the AI wave. However, there is still a
lot of misinformation and gaps in knowledge that need to be addressed.

I’ll go through this in the remainder of the article.

## Primer: Kubernetes vs. VMs

The most evident difference between Kubernetes and VMs is that while VMs run
operating systems, Kubernetes runs containerised applications and orchestrates
them. VMs don’t control applications running inside them and require external
tools to deploy them, with little to no insights into day-2 operations.

Let me clarify this with an example. The Deployment resource in Kubernetes is
designed to respond to expected and unexpected events that cause the desired
state to differ from the observed state. This might include a planned security
update of the underlying Kubernetes node hosting the operating system shared by
the containers: during a drain operation, this update requires all running
workloads to be smoothly moved to another Kubernetes node. It might also
include an unexpected event, such as the failure of a worker node hosting some
of those workloads, triggering a self-healing procedure that restores the
number of application replicas for high availability by moving them to another
available node. Similarly, auto-scaling capabilities can detect a lower
resource requirement for an application and scale it down automatically.

These patterns allow for **better and more efficient use of available
resources** and **cost optimisation**, often one of the top reasons for moving
to Kubernetes. Cost optimisation is further amplified by containers sharing the
underlying operating system installed on a worker node, making their footprint
much smaller than VMs, which each deploy an entire operating system.

**Kubernetes is more than just a deployment tool; it also handles day-2
operations**. While VMs require additional software to achieve similar
capabilities, Kubernetes extends to the infrastructural layer, taking on the
responsibility of applications' business continuity. This shift reduces
unnecessary bureaucracy, favours automation, and simplifies business continuity
plans within a single region.

VMs are often treated as mutable systems, hosting several applications. They
are upgraded, directly or indirectly, with imperative commands such as `dnf
update`. Conversely, **containers are immutable and should run a single
application**. They are upgraded by replacing them with a newer version of
their container image in a rolling update fashion. While this methodology
requires a change in how applications are deployed and distributed, it brings
numerous benefits from a security perspective and change management via
Infrastructure as Code. **The status of the entire Kubernetes cluster
intrinsically defines an organisation’s infrastructure at any given time.**

Even though VMs can be ported to every cloud provider, provisioning them in a
portable way requires additional software and complexities. In contrast, all
major providers offer Kubernetes services, **making the entire definition of
our infrastructure and application portfolio entirely portable across any cloud
environment**, including private, hybrid, and multi-cloud scenarios.

## The Operator Pattern: Essential for Databases

Regarding databases, VMs and Kubernetes’ standard resources are not sufficient.
However, one of the strengths of Kubernetes is the **operator pattern**, a
development pattern designed to manage complex applications like a PostgreSQL
database.

**I strongly advise against running a production database in Kubernetes without
using an operator** which understands the primary/standby architecture of
PostgreSQL and its configuration, can perform automated failover, switchover,
fencing, hibernation, backups, and point-in-time recovery, improves security by
default, and facilitates integration with observability tools like Prometheus,
Grafana, Fluentbit, etc.

As a maintainer and co-founder, I recommend CloudNativePG, an operator that
incorporates nearly 20 years of experience managing mission-critical production
databases with EDB and, previously, with 2ndQuadrant.

## Current State of Postgres Databases in Kubernetes

**Disclaimer:** _This is my personal opinion, shaped by the experiences and
challenges I've faced since starting the exciting journey of running PostgreSQL
databases in Kubernetes in 2019. My technical background is primarily as a
Postgres DBA and data warehousing architect, though I have been exposed to
DevOps and Lean practices for many years. Initially, the DBA in me was very
sceptical about Kubernetes, while my lean mindset pushed me to adopt a
fail-fast approach to this entire initiative. Moreover, my opinions revolve
around CloudNativePG and the conversations happening in its growing
community._

---

The holistic approach we've taken with CloudNativePG is showing very promising
results. Unlike most other operators, CloudNativePG has been designed from the
ground up for a Kubernetes audience. Our deliberate motto is:
_“Bringing Postgres to Kubernetes.”_ 

CloudNativePG is indeed more than an operator; it is a database management
platform that extends the Kubernetes controller. It teaches Kubernetes to
[directly understand and manage a PostgreSQL cluster](https://cloudnative-pg.io/documentation/current/controller/),
rather than relying on external tools (such as repmgr, which I contributed to
in the early stages, or Patroni) for critical operations like primary election,
async/sync replication, automated failover, switchover, configuration
management across the primary/standby architecture, backups, recovery,
monitoring, logging, and certificate management.

CloudNativePG also leverages the Kubernetes API, directly managing persistent
volume claims through storage classes without relying on stateful sets. It
supports volume snapshot backup and recovery, with the cluster's status stored
within Kubernetes itself. Additionally, our security-by-default approach
provides significant benefits, ensuring robust and secure management of
PostgreSQL databases in Kubernetes environments.

Some of us are actively involved in the [Data on Kubernetes Community](https://dok.community/),
the [TAG Storage](https://github.com/cncf/tag-storage) group from the CNCF, and the
[Kubernetes storage project](https://www.enterprisedb.com/blog/edb-engineer-leonardo-cecchi-recognized-valuable-storage-contributions-kubernetes).
Our engagement in these communities has been instrumental in shaping and
advancing the integration of PostgreSQL with Kubernetes. This level of
involvement and influence seemed unimaginable when we first participated in
KubeCon in San Diego in 2019, where we entered the landscape cautiously and
quietly. Since then, we've made significant strides, contributing to and
learning from these vibrant communities and helping to drive forward the state
of data management in Kubernetes.

CloudNativePG, which EDB open-sourced in May 2022, is distributed under the
Apache 2.0 license. Most importantly, it is vendor-neutral, owned by an
open-source community (not a company), and [openly governed](https://github.com/cloudnative-pg/governance/blob/main/GOVERNANCE.md).
It will always be open source with a very permissive license, **making the
entire stack (Kubernetes, PostgreSQL, and CloudNativePG) a safe long-term
choice for organisations**.

CloudNativePG is also becoming one of the most popular database operators at
[conferences like KubeCon and Kubernetes Community Days](https://events.linuxfoundation.org/?_sft_lfevent-category=kubecon-cloudnativecon-cncf-events),
with several talks (not just by me) over the last two years since it was
open-sourced.

In summary, we are leveraging our experience and providing the tools for others
to easily test and extend our claims, thereby challenging the misconception
that databases cannot run in Kubernetes. As an open-source enthusiast, it's
incredibly energising to have contributed to such a dynamic, organic, and
living movement. The quality and depth of questions and solutions discussed by
new community members in Slack channels are clear indicators of growth and the
ever-rising bar of excellence in this unexplored field.

It is also rewarding to see new generations of IT professionals born
cloud-native using PostgreSQL as their first database in Kubernetes, thanks to
CloudNativePG. This trend suggests that many startups will base their data
platforms on PostgreSQL and fully embrace the "PostgreSQL for everything"/"Just
use Postgres" wave, leveraging PostgreSQL's extensibility — including the
[pgvector](https://github.com/pgvector/pgvector) extension to make Postgres a
vector database.

These are just a few examples of the unique approaches that CloudNativePG has
taken, contributing to its growing popularity and increased adoption within the
Kubernetes community. However, there is still much work in other communities
and the enterprise sector.

## PostgreSQL Community

Our efforts so far have facilitated the adoption of Postgres in Kubernetes,
**primarily targeting Kubernetes adopters and audiences**. However, we now see
a **growing need for more PostgreSQL expertise in this intersection**.

This presents a **significant opportunity for all PostgreSQL DBAs**.

To capitalise on this, we must develop programs and materials to help DBAs get
up to speed on Kubernetes, highlighting the similarities and differences
between traditional deployments on VMs and bare metal. I intend to participate
in more PostgreSQL conferences this year (starting from the [Swiss PGDay on
June 28, 2024](https://www.pgday.ch/2024/#schedule)) and hear feedback from
that audience.

## Enterprise Infrastructure Teams

I have often noticed that teams responsible for infrastructure and Kubernetes
deployments in large enterprises are often unaware that databases can run in
Kubernetes. They tend to prefer keeping databases outside Kubernetes, opting to
run them as a service in the cloud (especially if no DBA team is present in the
organisation) or on virtual machines/bare metal deployments. This is largely
due to the lack of technical material tailored for solution architects on the
topic.

Wearing the EDB hat here: we need to build more awareness about possible
architectures and storage solutions by collaborating with enterprises that
support Kubernetes distributions (e.g., Red Hat for OpenShift).

CIOs might find this particularly appealing, especially in Europe, where
open-source mandates and the new [EU Data Act](https://eur-lex.europa.eu/eli/reg/2023/2854/oj)
encourage organisations to retain their data on their own infrastructure and
under their full control. The PostgreSQL, Kubernetes, and CloudNativePG
open-source stack presents a valuable asset in this context.

## Development Teams

Developers write applications to run in containers but often don't realise they
could leverage Kubernetes and PostgreSQL microservice databases. Probably
influenced by the opinion of the above infrastructure team, developers still
see the database as something external to the application instead of a
fundamental and controllable part of it.

Incorporating PostgreSQL into their CI/CD pipelines can lead to incredible
velocity and reliability. We need to build awareness and provide examples of
what this means, [leveraging the concepts of the microservice database highlighted in a previous article](https://www.gabrielebartolini.it/articles/2024/02/maximizing-microservice-databases-with-kubernetes-postgres-and-cloudnativepg/).

By addressing these areas, we can further enhance the adoption and effective
use of PostgreSQL in Kubernetes, ensuring it becomes a standard practice across
various sectors.

## Conclusions

As a recap, the major reasons for organisations to move to Kubernetes, based on
my experience, are:

- **Standardisation and Portability:** Kubernetes provides a consistent and
  portable infrastructure layer, reducing vendor lock-in risks.
- **Resource Optimization:** Kubernetes allows for efficient use of resources
  through container orchestration and automated scaling, with cost optimisation
  benefits.
- **Day-2 Operations:** Kubernetes, supported by robust operators, automates
  updates and self-healing, functions often absent or delegated in traditional
  VM-based setups.
- **Security and Change Management:** Containers' immutability and rolling
  updates offer significant security and operational benefits.
- **Increased Velocity:** Development teams can autonomously and swiftly
  deliver new features for their microservice applications through streamlined
  CI/CD pipelines. This approach empowers teams to iterate and deploy updates
  more efficiently, enhancing overall development speed and agility.

PostgreSQL's integration into Kubernetes environments presents significant
benefits in all the above-listed items. This article aims to spark internal
discussions within organisations worldwide and encourage consideration of this
powerful option.

As Kubernetes celebrates its tenth year, it coincides with the fifth year of
the Cloud Native PostgreSQL initiative, initiated in August 2019 during my
tenure at 2ndQuadrant. Reflecting on this rewarding journey, I eagerly
anticipate the next five years of innovation and growth. Before concluding, I
share a testimonial from CloudNativePG Community Member
[Wei-Yen Tan, Senior Platform Engineer at Datacom in New Zealand](https://www.linkedin.com/in/weiyentan/?originalSubdomain=nz):

> We chose to implement CNPG in our client's production environment to manage
> high-volume daily transactions across multiple locations. This component is
> critical to our operations. The operator's stability and automation have
> enabled our PostgreSQL engineers to focus on higher-value tasks. Initially
> sceptical about using PostgreSQL in containers due to data integrity
> concerns, I was pleasantly surprised by the logical and integrity-preserving
> data management during proof-of-concept testing. Recovery was
> straightforward, especially with local object storage solutions like MinIO.

## Further Readings

For a more comprehensive understanding and further insights on this topic, I
have compiled a list of related articles I have written in the past. These
resources provide a deeper dive into the nuances of PostgreSQL on Kubernetes
and the broader Cloud Native movement: 

- [Local Persistent Volumes and PostgreSQL usage in Kubernetes](https://www.2ndquadrant.com/en/blog/local-persistent-volumes-and-postgresql-usage-in-kubernetes/) (June 2020)
- [Why EDB chose immutable application containers](https://www.enterprisedb.com/blog/why-edb-chose-immutable-application-containers) (February 2021)
- [Introducing CloudNativePG: A New Open Source Kubernetes Operator for Postgres](https://www.enterprisedb.com/blog/introducing-cloudnativepg-new-open-source-kubernetes-operator-postgres) (May 2022)
- ["Custom Pod Controller" page from CloudNativePG documentation](https://cloudnative-pg.io/documentation/current/controller/) (May 2022)
- ["Recommended architectures for PostgreSQL in Kubernetes"](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/) (Sept 2023)
- [Maximising Microservice Databases with Kubernetes, Postgres, and CloudNativePG](https://www.gabrielebartolini.it/articles/2024/02/maximizing-microservice-databases-with-kubernetes-postgres-and-cloudnativepg/) (February 2024)
- [CloudNativePG Recipe #5 - How to migrate your PostgreSQL database in Kubernetes with ~0 downtime from anywhere](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-5-how-to-migrate-your-postgresql-database-in-kubernetes-with-~0-downtime-from-anywhere/) (March 2024)

By leveraging these insights and continuing to innovate, we can ensure that
PostgreSQL thrives within the Kubernetes ecosystem, paving the way for future
advancements and broader adoption.

_Cover Picture: [Two elephants engaged in friendly banter in Minneriya National Park](https://commons.wikimedia.org/wiki/File:Engaged_in_a_friendly_banter.jpg), licensed by Rohitvarma under the Creative Commons Attribution-Share Alike 4.0 International license._

---

_Keep an eye out for future updates! Be sure to follow my
[LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[X](https://twitter.com/_GBartolini_) channels to stay up-to-date. If you found
this article helpful, why not share it with your social media network using the
links below? Your support means a lot!_
