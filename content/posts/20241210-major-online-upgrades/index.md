---
title: "CNPG Recipe 15 - PostgreSQL major online upgrades with logical replication"
date: 2024-12-11T07:28:42+01:00
description: ""
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_This recipe shows how to perform an online major PostgreSQL upgrade using the
new declarative approach to logical replication introduced in CloudNativePG
1.25. By leveraging the `Publication` and `Subscription` CRDs, users can set up
logical replication between PostgreSQL clusters with ease. I will walk you
through configuring a PostgreSQL 15 publisher, importing schemas into a
PostgreSQL 17 subscriber, and verifying data synchronisation, with the broader
goal of highlighting the benefits of a repeatable and testable upgrade process._

<!--more-->

_NOTE: this article has been updated on December 23rd, 2024 with the most recent
version of `cloudnative-pg`._

---

Upgrading PostgreSQL to a major version has historically been one of the most
challenging tasks for users. To minimise downtime during the upgrade process,
two primary approaches are commonly used:

1. **Offline In-Place Upgrade**
   Using [`pg_upgrade`](https://www.postgresql.org/docs/current/pgupgrade.html)
   to ensure that the data files from an older version are converted to the newer
   version.

2. **Online Remote Upgrade**
   Leveraging native logical replication for minimal downtime. For a detailed
   guide, check out ["CNPG #5 - How to Migrate Your PostgreSQL Database in Kubernetes with ~0 Downtime from Anywhere"]({{< relref "../20240327-zero-cutover-migrations/index.md" >}}),
   as it covers concepts essential for fully understanding this article.


Although CloudNativePG does not currently support `pg_upgrade`
([planned for version 1.26](https://github.com/cloudnative-pg/cloudnative-pg/issues/4682)),
version 1.25 introduces a significant new feature:
[declarative support for logical publications and subscriptions](https://cloudnative-pg.io/documentation/preview/logical_replication/).

This article demonstrates how to perform an online major PostgreSQL upgrade on
your laptop using `kind` (Kubernetes in Docker). I'll use the `Publication` and
`Subscription` CRDs introduced in the version 1.25.

## Use Case: Online Major PostgreSQL Upgrade

Imagine you have a CloudNativePG-managed PostgreSQL 15 database running in your
Kubernetes cluster. Your goal is to upgrade it to PostgreSQL 17 while meeting
the following requirements:

- *Repeatability*: The process should be repeatable to ensure reliability.
- *Testability*: Run a test migration to provide ample time for developers
  and testers to validate the upgraded database. This also allows you to
  measure the time required for data transfer, and practice the cutover
  procedure.
- *Production-Readiness*: Ensure a fresh migration is performed from scratch
  before switching to the new database in production. This approach minimises
  downtime for the application, reducing it to near-zero levels.

## Installing CloudNativePG

Before proceeding, ensure you’ve completed the steps in
["CloudNativePG Recipe 1 - Setting Up Your Local Playground in Minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}}).
For this example, you’ll need version 1.25 to use the declarative `Publication`
and `Subscription` CRDs.

To install version 1.25.0, run the following command:

```sh
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.0.yaml
```

Make sure you also have the latest version of the `cnpg` plugin for `kubectl`,
as described in CloudNativePG Recipe #1.

## Setting Up the Origin Database

Let’s start by defining a PostgreSQL 15 cluster with the following
configuration:

```yaml
{{< include "yaml/pg-15.yaml" >}}
```

### Populating the Database with Sample Data

We’ll use `pgbench` to generate and insert sample data into the database. Run
the following command:

```sh
kubectl cnpg pgbench \
  --db-name app \
  --job-name pgbench-init \
  pg-15 \
  -- --initialize
```

After running the command, inspect the job logs to confirm the operation:

```sh
kubectl logs jobs/pgbench-init
```

You should see output similar to the following:

```output
dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
100000 of 100000 tuples (100%) of pgbench_accounts done (elapsed 0.01 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 0.16 s (drop tables 0.00 s, create tables 0.01 s, client-side generate 0.07 s, vacuum 0.04 s, primary keys 0.04 s).
```

At this point, the `app` database should contain the `pgbench` tables and be
approximately 22 MB in size. You can verify this by running:

```sh
kubectl cnpg psql pg-15 -- app -c '\dt+' -c '\l+'
```

## Setting Up the Destination Database

Next, you’ll define the PostgreSQL 17 cluster and configure it to import the
schema from its source, `pg-15`, which serves as the "publisher" in logical
replication terms:

```yaml
{{< include "yaml/pg-17.yaml" >}}
```

In the example above, the `externalClusters` section specifies how to connect
to the publisher using the `app` user.

Once the manifest is applied, the destination server will have the schema
imported but without any data. You can verify this by running:

```sh
kubectl cnpg psql pg-17 -- app -c '\dt+'
```

You should get a similar output:

```output
                                        List of relations
 Schema |       Name       | Type  | Owner | Persistence | Access method |  Size   | Description
--------+------------------+-------+-------+-------------+---------------+---------+-------------
 public | pgbench_accounts | table | app   | permanent   | heap          | 0 bytes |
 public | pgbench_branches | table | app   | permanent   | heap          | 0 bytes |
 public | pgbench_history  | table | app   | permanent   | heap          | 0 bytes |
 public | pgbench_tellers  | table | app   | permanent   | heap          | 0 bytes |
(4 rows)
```

## Setting Up the Publisher

The first step in configuring logical replication is enabling a role to be used
in a logical publication in the `app` database. For this example, we’ll use the
`app` user for simplicity. Below, we assign the `replication` privilege to the
`app` user:

```yaml
{{< include "yaml/pg-15-pub.yaml" >}}
```

We then create the `Publication` resource that will be then used to replicate
all changes to all tables in the `app` database.

```yaml
{{< include "yaml/pub.yaml" >}}
```

Apply the manifest and check the `app` user:

```sh
kubectl cnpg psql pg-15 -- app -c '\du app'
```
```output
      List of roles
 Role name | Attributes
-----------+-------------
 app       | Replication
```

## Setting Up the Subscriber

With the `pg-17` database schema imported, the next step is to configure the
subscription to the "publisher" on `pg-15`. This establishes logical
replication between the two clusters:

```yaml
{{< include "yaml/sub.yaml" >}}
```

Apply the manifest to initiate the subscription, then check the logs of both
clusters. You should see entries indicating that logical replication has
started, such as:

```
logical replication apply worker for subscription "subscriber" has started
```

or:

```
starting logical decoding for slot "subscriber"
```

Finally, verify that the `pgbench_accounts` table on the destination database
contains 10,000 records by running the following command:

```sh
kubectl cnpg psql pg-17 -- app -qAt -c 'SELECT count(*) FROM pgbench_accounts'
```

Once you have migrated, you can delete the subscription and publication
objects.

## Conclusions

This article introduced the basics of setting up logical replication using the
new declarative approach in CloudNativePG 1.25. While the focus was on core
concepts, there are additional aspects to consider, such as synchronising
sequences—which are not part of the `pgbench` database. Detailed guidance on
this topic is available in [CNPG Recipe #5](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-5-how-to-migrate-your-postgresql-database-in-kubernetes-with-~0-downtime-from-anywhere/)
through the use of plugins— this task is still imperative or delegated to the
application.

For cutover, transitioning your applications to the new `pg-17-rw` service will
finalise the process. If your publisher resides outside the control of
CloudNativePG, you can still benefit from the declarative subscriptions.

The primary goal of this article was to showcase the streamlined and repeatable
process for managing PostgreSQL native logical replication through the new
declarative method for defining publications and subscriptions. This approach
significantly enhances the manageability and efficiency of logical replication
in Kubernetes environments.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephant Family with baby“](https://www.flickr.com/photos/barbourians/6168258059)._

