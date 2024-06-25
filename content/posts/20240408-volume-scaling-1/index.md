---
title: "CloudNativePG Recipe 6: Postgres Vertical Scaling with Storage - part 1"
date: 2024-04-08T19:37:50+02:00
description: "Uncover PostgreSQL's surprising vertical scalability in this first of a two-part series, exploring resource optimization within a single node and robust strategies in the CloudNativePG framework"
tags: ["PostgreSQL", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "DoK", "data on kubernetes", "CNPG", "vertical scalability", "storage", "cpu", "ram", "benchmarking", "PVC", "WAL", "tablespaces", "I/O separation", "horizontal scalability"]
cover: cover.png
thumb: thumb.png
draft: false
---

_Are you worried that PostgreSQL cannot scale writes within a single node, or do
you think that scaling PostgreSQL can only be done horizontally, across
different Kubernetes nodes? Discover the surprising truth behind PostgreSQL's
vertical scalability in this first article of a two-part series. Explore the
potential of optimizing CPU, RAM, and storage resources through meticulous
measurement and benchmarking, challenging conventional scaling wisdom. Delve
into the solid strategies within the CloudNativePG stack, such as separate
volumes for data and transaction logs, temporary tablespaces, and I/O
segregation for tables and indexes. Stay tuned for insights into aligning
storage solutions with PostgreSQL's resilience needs in the upcoming sequel._

<!--more-->

---

During KubeCon EU 2024 in Paris, I delivered a talk with Gari Singh from Google
Cloud titled “Scaling Heights: Mastering Postgres Database Vertical Scalability
with Kubernetes Storage Magic” (the
[video of that talk is available on the CNCF channel on YouTube](https://www.youtube.com/watch?v=LArl0VWxr3Y&ab_channel=CNCF%5BCloudNativeComputingFoundation%5D)).

A PostgreSQL database cluster comprises a single primary with an arbitrary
number of read-only replicas for High Availability. One of the biggest mistakes
we could make is quickly jumping to conclusions and labelling Postgres as a
database that cannot scale. The goal of that presentation was to remind us that
scaling doesn’t necessarily imply doing it horizontally - that is, across
different nodes. Scaling can also happen on a single node by taking full
advantage of all the available CPU, RAM, and storage resources.

Like that presentation, this two-part blog series will focus on the most
critical component for a database’s vertical scalability: storage.

# Start simple

Although there are several use cases where horizontal scaling is required, I
advise starting simple, adopting a scientific approach, and measuring your
database systems before taking that path. The reason is purely pragmatic: a
PostgreSQL cluster is much simpler to manage regarding Disaster Recovery and
High Availability than an active/active counterpart that spans across different
nodes, for example.

Start by defining your business goals: Recovery Point Objective (RPO), Recovery
Time Objective (RTO), and the number of transactions per second (TPS) that you
require. Then benchmark PostgreSQL, and only if the results are not good enough
proceed with an active/active distributed solution. Benchmark the
[storage with `fio`](https://cloudnative-pg.io/documentation/current/benchmarking/#fio)  and
the [database using `pgbench`](https://cloudnative-pg.io/documentation/current/benchmarking/#pgbench)
(either with the built-in OLTP-like workload or by writing your custom
queries).

In any case, fine-tuning PostgreSQL to exploit each node entirely is an
activity that will bring benefits even in a distributed scenario.

# Scaling with volumes in CloudNativePG

CloudNativePG is designed to manage `PersistentVolumeClaim` (PVC) resources
directly instead of relying on a `Statefulset` resource like most operators
that work with data (another one that followed our approach is
[Strimzi for Kafka](https://github.com/strimzi/strimzi-kafka-operator/blob/main/CHANGELOG.md#0350)).
If you are interested, we explain the reasons behind this choice on the
[“Pod Controller” page from the CloudNativePG documentation](https://cloudnative-pg.io/documentation/current/controller/).

Every CloudNativePG instance necessitates a mandatory volume for the PostgreSQL
data, aka `PGDATA`, meticulously configured within the `storage` stanza.

Flexibility is vital with CloudNativePG, as it includes an optional volume for
Write Ahead Log (WAL) files, configured via the `walStorage` stanza, bolstering
data protection and recovery capabilities. CloudNativePG empowers you to create
an arbitrary number of PostgreSQL tablespaces through the `tablespaces` stanza,
effectively decoupling physical and logical data modelling.

Additionally, CloudNativePG offers the freedom to use different storage classes
for each volume, catering to diverse storage requirements and preferences and
optimising cost-efficiency and I/O bandwidth for specific volume purposes. For
example, you can use a different storage class for WAL file storage or a
particular tablespace.

You can add volumes to live clusters and resize them (subject to storage class
support), ensuring adaptability to evolving storage needs. The primary
advantages of scaling with volumes include performance isolation and
predictability, effective I/O distribution across volumes, and streamlined
database maintenance operations such as indexing, reindexing, or `VACUUM`.

Regardless of the number of PVCs, integration with High Availability and
Disaster Recovery is seamless, facilitated by features like volume snapshot
backup and recovery for large databases.

Knowing the strengths and weaknesses of your CSI solutions is essential for
making informed decisions and effectively managing PostgreSQL databases in a
Kubernetes environment.

# Adding a separate volume for WAL files

The first option you have is to move the transaction logs (WAL files) onto
another volume. All you must do is add the `walStorage` stanza as in the
example below:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: separate-wal
spec:
  instances: 3
  storage:
    size: 40Gi
  walStorage:
    size: 10Gi
```

Each instance within the `separate-wal` cluster will be equipped with two
volumes: one designated for `PGDATA` and another dedicated to WAL files.
Internally, CloudNativePG manage the symbolic link to ensure that the
`pg_wal` directory seamlessly points to the appropriate directory within the
WAL volume. In the event of adding a volume for WAL files later on,
CloudNativePG orchestrates a smooth
[rolling update](https://cloudnative-pg.io/documentation/current/rolling_update/#automated-updates-unsupervised)
process. This involves halting replicas one at a time, transferring WAL files
to the new volume, and updating symbolic links. The process is further refined
by the `primaryUpdateMethod` option, which dictates whether the primary
undergoes a restart or a switchover.

Employing a dedicated volume for WAL files yields tangible enhancements in
database performance. Specifically, some
[benchmarks I have run](https://github.com/gbartolini/postgres-kubernetes-playground/tree/main/tablespaces#results)
show an improvement between 15% and 45%, depending on how much your access
workload is on disk vs in memory.

The critical aspect here is to properly size the volume for WALs and make it
coherent with PostgreSQL settings such as `min_wal_size` and `max_wal_size`.
Running out of disk space in the WAL volume will force PostgreSQL to halt
([there is an ongoing discussion on improving this in CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg/discussions/3775)).

The critical point is the ability to use a WAL-optimised storage class
different from the one used for PGDATA. For example:

```yaml
  walStorage:
    storageClass: my-favourite-storage-class-for-wals
    size: 10Gi
```

# Adding temporary tablespaces

In PostgreSQL, you can set up one or more temporary tablespaces. They are handy
for creating temporary objects, namely temporary tables and indexes. They're
also used to make temporary files to sort big data sets. You can find many
resources online to learn more about temporary tablespaces. For the interactive
approach he used, I like
[the article Daniel Westermann wrote a few years ago](https://www.dbi-services.com/blog/about-temp_tablespaces-in-postgresql/).

Internally, PostgreSQL controls temporary tablespaces via the
`temp_tablespaces` parameter, which supports multiple occurrences.
CloudNativePG abstracts the management of this parameter through the
`.spec.tablespaces[*].temporary` option.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: tmp-tablespace
spec:
  instances: 3
  storage:
    size: 40Gi
  walStorage:
    size: 10Gi
  tablespaces:
  - name: tmptbs1
    temporary: true
    storage:
      size: 40Gi
```

You can verify that the `tmptbs1` tablespace is in the `temp_tablespaces`
parameter as follows:

```sh
kubectl exec -ti tmp-tablespace-1 -c postgres \
  -- psql -c 'SHOW temp_tablespaces'
```

Returning:

```console
 temp_tablespaces
------------------
 tmptbs1
(1 row)
```

As mentioned, you could even add a second temporary tablespace:

```yaml
# <snip>
  tablespaces:
  # <snip>
  - name: tmptbs2
    temporary: true
    storage:
      size: 40Gi
```

The same `kubectl` command will now return:

```console
 temp_tablespaces
------------------
 tmptbs1,tmptbs2
(1 row)
```

In this case, when PostgreSQL creates a temporary object inside a transaction,
it randomly picks one from the `temp_tablespaces` list and then sequentially
iterates through it.


# Separating I/O for indexes and tables

A widely used technique, particularly effective with simpler databases and
scenarios, involves separating I/O operations for tables and indexes. In this
example, we create two tablespaces: `data` for tables and `idx` for indexes.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: idx-tablespace
spec:
  instances: 3
  storage:
    size: 40Gi
  walStorage:
    size: 10Gi
  tablespaces:
  - name: data
    storage:
      size: 40Gi
  - name: idx
    storage:
      size: 40Gi
```

Once the tablespaces are there, you can position a table in the `data`
tablespace by specifying the `TABLESPACE` option in the Data Definition
Language (DDL) statement that creates the table. Given that this will also
place any index for that table in the `data` tablespace, you must create:

- constraints by specifying `USING INDEX TABLESPACE idx`
- indexes by specifying `TABLESPACE idx`

# What’s next

By now, you have understood the flexibility the CNPG stack (Kubernetes,
PostgreSQL, and CloudNativePG) provides regarding storage. As with any
[paradox of choice](https://www.ted.com/talks/barry_schwartz_the_paradox_of_choice),
the risk is for you to get lost in the ocean of possibilities.
Start simple, then evaluate the storage possibilities you have based on the
underlying Kubernetes environment.

Work with storage vendors, especially on-premises, and make them do the work
for you (trust me, they'll be happy to do it!).
As shown in the KubeCon talk, I published a straightforward set of
[benchmarking guidelines](https://github.com/gbartolini/postgres-kubernetes-playground/tree/main/tablespaces)
that they can use to start providing some valuable insights.

Pay attention to performance, but make sure you don’t lose any data at the
storage level (for example, what happens if you suddenly shut down the
underlying hardware and storage?). PostgreSQL is designed from the ground up to
be resilient to these issues. Remember that
[planning and practice environments](https://itrevolution.com/articles/moving-from-the-danger-zone-to-the-winning-zone/)
are the perfect places to run these critical experiments: you don’t want to
discover that your storage layer doesn’t honour data durability in the
performance environment (i.e., operations, production, or execution).

In the [next article]({{< relref "../20240416-volume-scaling-2/index.md">}}),
I continue covering the vertical scalability of PostgreSQL databases with
storage, focusing on tablespaces and horizontal table partitioning.

---

_Please stay tuned for upcoming updates! To keep yourself informed, kindly
follow my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[X](https://twitter.com/_GBartolini_) channels. If you found this article
helpful, why not share it with your social media network using the links below?
Your support would mean a lot to me!_
