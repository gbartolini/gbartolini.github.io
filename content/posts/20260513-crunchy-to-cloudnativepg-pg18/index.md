---
title: "CNPG Recipe 24 - Migrating from Crunchy PGO to PostgreSQL 18 with CloudNativePG"
date: 2026-05-13T20:21:26+10:00
description: "A step-by-step guide to migrating a Crunchy PGO v6 PostgreSQL 17 database to PostgreSQL 18 with CloudNativePG, using a minimal operand image with the pgaudit extension as an OCI image volume for a smaller footprint and reduced attack surface."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "dok", "data on kubernetes", "migration", "crunchy", "pgo", "percona", "logical-replication", "pg-dump", "major-upgrade", "postgresql-18", "publication", "subscription"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_A step-by-step guide to migrating a PostgreSQL 17 cluster managed by Crunchy
PGO v6 to PostgreSQL 18 under CloudNativePG. Two paths are covered: a fully
declarative offline migration using CloudNativePG's built-in `pg_dump` import,
and an online migration using native PostgreSQL logical replication for a
near-zero-downtime cutover._

<!--more-->

---

Since
[Crunchy Data was acquired by Snowflake](https://www.snowflake.com/en/news/press-releases/snowflake-acquires-crunchy-data-to-bring-enterprise-ready-postgres-offering-to-the-ai-data-cloud/)
roughly a year ago, I have heard the same concern repeatedly in my work at EDB,
talking with prospects and teams evaluating PostgreSQL on Kubernetes:
uncertainty about the future of Crunchy PGO. The questions vary (around
long-term commitment to the open-source operator, release cadence, community
activity) but the underlying worry is consistent. I should be transparent: my
direct knowledge of the Crunchy operator is limited, given how fundamentally
different its architecture is from CloudNativePG's, and any opinion I might
offer on its future would be speculative at best. What matters here is the
practical question: if you are considering your options, what does the migration
path look like? If you are running a Crunchy PGO v6 cluster and considering your
options, this recipe shows you exactly how to migrate to CloudNativePG while
upgrading to PostgreSQL 18 in the same operation. Two paths are covered: an
**offline** path using CloudNativePG's built-in
[`pg_dump` import](https://cloudnative-pg.io/docs/current/database_import/), and
an **online** path using native PostgreSQL
[logical replication](https://cloudnative-pg.io/docs/current/logical_replication/)
for a near-zero-downtime cutover.

From CloudNativePG's perspective, the source of a migration is simply a
PostgreSQL endpoint reachable over the network. It does not matter whether that
endpoint is managed by Crunchy PGO, Zalando, Patroni, RDS or anything else. What
matters is that the database is accessible, a user with sufficient privileges
exists and (for the online path) the source supports logical replication.
Everything else is standard PostgreSQL and CloudNativePG mechanics.

This recipe builds on
[CNPG Recipe 5]({{< relref "../20240327-zero-cutover-migrations/index.md" >}})
and the declarative logical replication introduced in
[CNPG Recipe 15]({{< relref "../20241210-major-online-upgrades/index.md" >}}).
The Crunchy PGO cluster is treated as a black box: we apply a manifest to stand
it up, note the service endpoint and the credentials secret it creates, and hand
that information to CloudNativePG. No knowledge of PGO internals is required.

The two paths diverge only at the point where the CloudNativePG cluster is
created. The offline path is the simpler of the two: the entire migration is
expressed as a single `Cluster` manifest, fully declarative end to end, with no
replication setup required. A maintenance window is needed, proportional to
dataset size.

The online path uses native PostgreSQL logical replication to keep data flowing
continuously from source to destination, reducing the cutover window to seconds
regardless of dataset size, at the cost of a few additional steps to set up and
tear down the replication objects.

If the `pg_dump` window fits within what your workload can tolerate, read the
offline section and stop. If it does not, continue to the online section.

The steps below use Kind as a local Kubernetes environment, but the manifests
are plain YAML and work unchanged against any conformant cluster. If you already
have a cluster with a running PGO deployment, skip directly to the migration
sections.

## Prerequisites

[CNPG Recipe 1]({{< relref "../20240303-recipe-local-setup/index.md" >}}) covers
the full local playground setup and walks through installing all of the tools
listed below. If this is your first time working with CloudNativePG, start
there.

- [Docker](https://www.docker.com/)
- [Git](https://git-scm.com/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) with the
  [cnpg plugin](https://cloudnative-pg.io/docs/current/kubectl-plugin/)

## Set up the local environment

Create a Kind cluster and install CloudNativePG:

```bash
kind create cluster --name cnpg-migration
kubectl config use-context kind-cnpg-migration
```

Install CloudNativePG using the operator manifest. Retrieve the URL for the
latest stable release from the
[installation page](https://cloudnative-pg.io/docs/current/installation_upgrade/#directly-using-the-operator-manifest),
then apply it:

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.1.yaml
  # replace with the latest release URL from the installation page
```

Wait for the operator to become available:

```bash
kubectl rollout status deployment \
  -n cnpg-system cnpg-controller-manager
```

Then apply the CloudNativePG extension image catalog. This catalog provides
pgaudit and other extensions as OCI images, delivered to each pod via the
Kubernetes `ImageVolume` feature (available by default from Kubernetes 1.35; on
1.33 and 1.34 the `ImageVolume` feature gate must be enabled explicitly):

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/refs/heads/main/image-catalogs-extensions/catalog-minimal-trixie.yaml
```

Inspect the catalog to see which PostgreSQL versions and extension images are
available:

```bash
kubectl describe clusterimagecatalog postgresql-minimal-trixie
```

## Deploy the source PostgreSQL 17 cluster

Although this recipe uses PGO v6, the migration steps from the CloudNativePG
side are identical for PGO v5: both versions use the same service and secret
naming conventions, and CloudNativePG connects to the PostgreSQL endpoint
directly without any knowledge of the operator managing it. If you are already
running a v5 cluster, skip this section entirely and proceed to the migration
steps using your existing endpoint and credentials.

Install Crunchy Postgres for Kubernetes (PGO) following the
[official quickstart](https://access.crunchydata.com/documentation/postgres-operator/latest/quickstart).
Clone the operator repository, check out the latest release tag, and apply the
Kustomize targets:

```bash
git clone https://github.com/CrunchyData/postgres-operator.git
cd postgres-operator
git checkout v6.0.1
kubectl apply -k config/namespace
kubectl apply --server-side -k config/default
cd ..
```

Check the
[releases page](https://github.com/CrunchyData/postgres-operator/releases) for
the current tag to use in place of `v6.0.1`.

Now deploy the source `PostgresCluster`. The manifest creates an `app` database
with a regular application user ( `app`) and a dedicated migration user (
`cnpg`) that CloudNativePG will use to connect. `wal_level: logical` is
included; it is required by the online path and harmless for the offline path.
No explicit image tags are needed: PGO v6 resolves the correct container images
automatically from `postgresVersion`.

A note on the database name before you apply. The name `app` here is symbolic;
substitute it with the name of the database you are migrating. CloudNativePG's
recommended pattern is one cluster per database (the microservice model). If the
source contains several databases, run this process separately for each one. See
the
[CloudNativePG FAQ](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/faq.md)
before considering any deviation from that pattern.

[`postgres-cluster-source.yaml`](yaml/postgres-cluster-source.yaml)

```yaml
{{< include "yaml/postgres-cluster-source.yaml" >}}
```

The `cnpg` user is granted `SUPERUSER` to keep this recipe self-contained. In
production, grant only the privileges required for the operations CloudNativePG
will perform on the source.

Once PGO has reconciled the cluster, two values are relevant for the rest of
this recipe:

- Primary endpoint: `crunchy-primary.default.svc` (port 5432)
- Migration credentials: secret `crunchy-pguser-cnpg`, key `password`

Check the cluster status until all instances report healthy:

```bash
kubectl describe postgresclusters.postgres-operator.crunchydata.com crunchy
```

### Load sample data

The following Job creates an `orders` table with a `SERIAL` primary key and
inserts 1,000 rows. This simulates an existing workload in the local
environment; in a real migration the data is already there and this step is
skipped entirely:

[`sample-data-init.yaml`](yaml/sample-data-init.yaml)

```yaml
{{< include "yaml/sample-data-init.yaml" >}}
```

Verify the data is present and check the current sequence value:

```bash
kubectl run psql-check --rm -it --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie \
  --env="PGPASSWORD=$(kubectl get secret crunchy-pguser-cnpg \
    -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h crunchy-primary.default.svc -U cnpg app \
     -c "SELECT count(*) FROM orders;" \
     -c "SELECT last_value FROM orders_id_seq;"
```

The source is ready: a live PostgreSQL 17 instance accessible at
`crunchy-primary.default.svc`, with data, a sequence at 1000 and a superuser
named `cnpg`.

### Check extension compatibility

Crunchy PostgreSQL images install `pgaudit` by default. The destination cluster
must also have pgaudit available, or `pg_restore` will fail when it encounters
`CREATE EXTENSION pgaudit` in the dump.

Both cluster manifests in this recipe use `imageCatalogRef` to reference the
`postgresql-minimal-trixie` catalog installed earlier, and declare `pgaudit` in
`spec.postgresql.extensions`. CloudNativePG mounts the pgaudit extension image
as a read-only volume on each pod via the Kubernetes `ImageVolume` feature,
making the extension available to PostgreSQL 18 without embedding it in the base
operand image. The pgaudit GUC parameters are set in
`spec.postgresql.parameters`, which CloudNativePG manages automatically. The
extension will be created cleanly during import.

For a real migration, audit the full extension list on the source first (
`SELECT extname FROM pg_extension`) and confirm each one is either available in
the destination image or can be provided via an extension image in the catalog
before starting.

## Offline migration

This is the fully declarative path. Apply the following `Cluster` manifest:

[`cluster-offline.yaml`](yaml/cluster-offline.yaml)

```yaml
{{< include "yaml/cluster-offline.yaml" >}}
```

CloudNativePG connects to the source, runs `pg_dump` on the `app` database and
restores the full schema and data into the new PostgreSQL 18 cluster. The import
runs once, at bootstrap. There is nothing else to configure for the migration
itself.

Wait for the cluster to become ready:

```bash
kubectl wait --for=condition=Ready cluster/pg-app --timeout=600s
```

Verify row counts and sequence values match the source:

```bash
# Source
kubectl run psql-count --rm -it --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie \
  --env="PGPASSWORD=$(kubectl get secret crunchy-pguser-cnpg \
    -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h crunchy-primary.default.svc -U cnpg app \
     -c "SELECT count(*) FROM orders;" \
     -c "SELECT last_value FROM orders_id_seq;"

# Destination
kubectl cnpg psql pg-app -- app \
  -c "SELECT count(*) FROM orders;" \
  -c "SELECT last_value FROM orders_id_seq;"
```

Once counts match, scale `pg-app` to the desired replica count and redirect your
application to `pg-app-rw.default.svc`. The migration is complete.

## Online migration

Use this path when the dataset is large enough that the `pg_dump` window is
unacceptable. Logical replication runs continuously alongside production,
reducing cutover to the seconds it takes to drain the replication queue. It
requires PostgreSQL 10 or later on the source, which covers every currently
supported PostgreSQL version.

### Deploy the destination cluster

The manifest is identical to the offline path, with one change:
`schemaOnly: true` instructs CloudNativePG to import only the schema at
bootstrap. Row data arrives via the subscription set up in the next step.

[`cluster-online.yaml`](yaml/cluster-online.yaml)

```yaml
{{< include "yaml/cluster-online.yaml" >}}
```

Wait for the cluster to become ready:

```bash
kubectl wait --for=condition=Ready cluster/pg-app --timeout=300s
```

Confirm the schema arrived but the tables are empty:

```bash
kubectl cnpg psql pg-app -- app -c '\dt+'
```

### Set up logical replication

Create the publication on the source using the `cnpg` plugin. It derives the
connection details from the `crunchy` external cluster entry in `pg-app` 's
spec:

```bash
kubectl cnpg publication create pg-app \
  --external-cluster crunchy \
  --publication migration \
  --all-tables
```

In CloudNativePG, the declarative `Subscription` resource handles this:

[`subscription.yaml`](yaml/subscription.yaml)

```yaml
{{< include "yaml/subscription.yaml" >}}
```

CloudNativePG creates the subscription and begins the initial table
synchronisation immediately. Confirm it has started:

```bash
kubectl logs \
  -l cnpg.io/cluster=pg-app \
  --follow \
  | grep -i "logical replication"
```

You should see
`logical replication apply worker for subscription "migration" has started`. Row
data will now flow continuously from the source into `pg-app`.

### Verification and cutover

Before the actual cutover, run at least one rehearsal to measure replication lag
and practise the sequence. Inspect the replication slot on the source:

```bash
kubectl run psql-lag --rm -it --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie \
  --env="PGPASSWORD=$(kubectl get secret crunchy-pguser-cnpg \
    -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h crunchy-primary.default.svc -U cnpg app -c "
    SELECT slot_name,
           confirmed_flush_lsn,
           pg_current_wal_lsn(),
           pg_current_wal_lsn() - confirmed_flush_lsn AS lag_bytes
    FROM pg_replication_slots
    WHERE slot_name = 'migration';"
```

When `lag_bytes` is consistently near zero, the subscription is caught up. At
this point the rows are in the destination, but logical replication does not
replicate sequences. Check the destination sequence value before synchronising:

```bash
kubectl cnpg psql pg-app -- app \
  -c "SELECT last_value FROM orders_id_seq;"
```

The value will be 1 (the default for an unadvanced sequence), regardless of how
many rows have been replicated. Synchronise the sequence before cutover:

```bash
kubectl cnpg subscription sync-sequences pg-app \
  --subscription migration
```

Run it once before the maintenance window as a rehearsal, and once more
immediately before redirecting traffic. Check the destination sequence again to
confirm it now matches the source:

```bash
kubectl cnpg psql pg-app -- app \
  -c "SELECT last_value FROM orders_id_seq;"
```

It is important to note that PostgreSQL 19 is expected to introduce native
support for replicating sequence state through
[`CREATE PUBLICATION`](https://www.postgresql.org/docs/devel/sql-createpublication.html)
and
[`CREATE SUBSCRIPTION`](https://www.postgresql.org/docs/devel/sql-createsubscription.html)
objects, which would make this manual step unnecessary. That capability is a
strong candidate for a future CloudNativePG integration.

When ready to go live, stop writes to the source. Wait for `lag_bytes` to reach
zero and run a final `sync-sequences`. Scale `pg-app` to the desired replica
count and redirect your application to `pg-app-rw.default.svc`.

Once you have confirmed the application is operating correctly, clean up the
replication objects:

```bash
# Delete the Subscription resource
# (subscriptionReclaimPolicy: delete drops the underlying SQL subscription)
kubectl delete subscription pg-app-migration

# Drop the publication on the source
kubectl cnpg publication drop pg-app \
  --external-cluster crunchy \
  --publication migration
```

## Cleaning up

With the application running stably on `pg-app`, decommission the source
cluster:

```bash
kubectl delete postgrescluster crunchy
```

The PGO operator and its namespace can be removed once all databases have been
migrated.

The `bootstrap.initdb.import` stanza and the `externalClusters` entry for
`crunchy` are only consulted during the initial bootstrap and have no effect on
a running cluster. Once the migration is complete, you can remove both sections
from the `Cluster` manifest and apply the change. CloudNativePG will reconcile
without any disruption.

To tear down the local Kind environment used in this recipe:

```bash
kind delete cluster --name cnpg-migration
```

## Image footprint and security posture

Migrating to CloudNativePG also changes the image stack you are pulling and
operating. The tables below quantify that change. Pull sizes are compressed
figures measured from OCI manifest layer data; vulnerability counts are from
`docker scout quickview`.

**Compressed pull sizes**

| Image | Role | Compressed pull size |
|---|---|---|
| `registry.developers.crunchydata.com/crunchydata/crunchy-postgres:ubi9-17.9-2610` | PGO source cluster | ~346 MB |
| [`ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie`](https://github.com/cloudnative-pg/postgres-containers) | CNPG destination (this recipe) | ~87 MB |
| [pgaudit extension image](https://github.com/cloudnative-pg/postgres-extensions-containers/tree/main/pgaudit) | pgaudit OCI image volume | ~44 KB |
| `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.12.0` | CNPG backup plugin | ~40 MB |
| **CNPG minimal + pgaudit + Barman Cloud Plugin** | **destination total** | **~127 MB** |

**CVE exposure ( `docker scout quickview` )**

| Image | Packages | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| `crunchy-postgres:ubi9-17.9-2610` | 625 | 2 | 156 | 1053 | 201 |
| `postgresql:18-minimal-trixie` | 140 | **0** | **4** | **6** | 39 |

The CNPG minimal-trixie image is a Debian Trixie Slim base containing only
PostgreSQL 18, with extensions delivered as OCI image volumes. The full
destination stack (operand, pgaudit extension image, Barman Cloud Plugin) comes
to approximately 127 MB, compared to 346 MB for the Crunchy source operand
alone. The CVE reduction is even more pronounced: 140 packages against 625, zero
critical vulnerabilities against two, and four high against 156. The package
count matters beyond the headline numbers: fewer packages means a smaller blast
radius for any future disclosure. The CNPG minimal image also ships with a full
SBOM provenance attestation, making it straightforward to audit exactly what is
in the image.

## Conclusions

Both migration paths reduce to a `Cluster` manifest and the connection details
for the source. The offline path is the shorter of the two: the entire migration
is a single declarative resource, applied once. The online path adds a
`Publication`, a `Subscription` and the `sync-sequences` step, but makes the
cutover window independent of dataset size. The same approach applies equally to
the
[Percona Operator for PostgreSQL](https://docs.percona.com/percona-operator-for-postgresql/latest/),
which uses identical service and secret naming conventions.

The `Cluster` manifests in this recipe are intentionally minimal: one instance,
no backup configuration, no resource limits. They are here for didactical
purposes only. In production you would run at least three instances, configure
WAL archiving and backups via the Barman Cloud Plugin before redirecting
traffic, and set appropriate resource requests and limits. The
[CloudNativePG documentation](https://cloudnative-pg.io/docs/current/) covers
all of these; treat the manifests here as a starting point, not a production
template.

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

_Cover Picture:
["Elephant vs hippo"](https://www.flickr.com/photos/andrewnapier/2637827351/). _
