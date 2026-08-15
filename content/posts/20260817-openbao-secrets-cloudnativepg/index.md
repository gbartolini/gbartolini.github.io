---
title: "CNPG Recipe 27 - Running OpenBao on Kubernetes with a CloudNativePG
  PostgreSQL backend"
date: 2026-08-17T09:30:00+11:00
description: "How to run OpenBao on Kubernetes with CloudNativePG as its
  synchronously replicated, cert-only PostgreSQL backend, with no passwords
  anywhere in the stack."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg",
  "dok", "data on kubernetes", "openbao", "vault", "hashicorp-vault",
  "secrets-management", "mtls", "tls", "certificates", "cert-authentication",
  "databaserole", "roles", "security", "high-availability",
  "synchronous-replication", "helm", "operator", "declarative-configuration",
  "separation-of-concerns", "disaster-recovery", "backup", "pg_hba"]
cover: cover.png
thumb: thumb.png
draft: true
---

_A walkthrough of running [OpenBao](https://openbao.org/) on Kubernetes with
[CloudNativePG](https://cloudnative-pg.io/) as its PostgreSQL storage
backend. Every layer of this stack is open source, with no vendor lock-in:
[Kubernetes](https://kubernetes.io/) and CloudNativePG are both CNCF
projects, authenticated entirely over TLS client certificates via the 1.30
`DatabaseRole` CRD, with no passwords anywhere in the stack. Co-authored
with [Rob Kenefeck](https://www.linkedin.com/in/robkenefeck) from
[ControlPlane](https://controlplane.io)._

<!--more-->

---

Managing infrastructure secrets on Kubernetes needs a backend that is
self-healing and free of vendor lock-in, and that is exactly what
[OpenBao](https://openbao.org/) (the Linux Foundation's open-source fork of
HashiCorp Vault) and [CloudNativePG](https://cloudnative-pg.io/) give you:
an entirely open-source stack built on two CNCF projects,
[Kubernetes](https://kubernetes.io/), long since graduated, and
CloudNativePG, a CNCF Sandbox project currently
[under evaluation for Incubation](https://github.com/cncf/toc/issues/1961)
by the CNCF Technical Oversight Committee. OpenBao's `postgresql` storage
backend turns any PostgreSQL cluster into its encrypted key-value store,
and CloudNativePG turns that cluster into a self-healing, synchronously
replicated, certificate-authenticated Postgres instance with no cloud
database dependency underneath it.

This recipe deploys a three-instance CNPG cluster as OpenBao's storage
backend and removes every password from the connection: the schema-owning
role and the application role OpenBao itself uses both authenticate with a
`DatabaseRole`-issued TLS client certificate, enforced by explicit `pg_hba`
rules rather than by the absence of a password. `pg_hba.conf` is
PostgreSQL's client-authentication file, the thing that actually decides,
per connection, whether a role needs a certificate, a password, or nothing
at all.

---

## Setting up a local test environment with `cnpg-playground`

Nothing about this recipe is specific to any one Kubernetes distribution:
any conformant cluster with enough worker capacity will do. To follow along
locally, though, the official
[`cnpg-playground`](https://github.com/cloudnative-pg/cnpg-playground)
repository is the fastest path to one, since it is pre-configured with the
CloudNativePG operator already. It is designed primarily around CNPG's own
demos, so it is worth knowing what it actually gives you: a single Kind
cluster with six nodes, a control plane node, one node labelled for
infrastructure workloads, one labelled for application workloads, and three
carrying a `node-role.kubernetes.io/postgres` taint. That taint is exactly
what our `Cluster`'s tolerations in Step 1 target, and it is also what
leaves OpenBao itself with only the two general-purpose nodes to schedule
onto, which matters once pod anti-affinity enters the picture in Step 3.
`setup.sh` provisions one Kind cluster per argument it is given, normally
used to model separate regions; passing it a single, arbitrary label gives
you one local cluster and skips the two-region disaster recovery demo
entirely.

Prerequisites: [Docker](https://www.docker.com/),
[Kind](https://kind.sigs.k8s.io/), [Helm](https://helm.sh/) and `kubectl`.

```bash
# Clone the CNPG Playground repository
git clone https://github.com/cloudnative-pg/cnpg-playground.git
cd cnpg-playground

# 1. Provision a single local cluster labelled "openbao"
./scripts/setup.sh openbao

# 2. Deploy CloudNativePG, cert-manager, the Barman Cloud plugin and a
#    ClusterImageCatalog only, skipping the demo databases
REQUIREMENTS_ONLY=true ./demo/setup.sh
```

---

## Architecture blueprint

![Architecture blueprint: three OpenBao pods connect over mTLS as the
openbao-rw role to the CloudNativePG RW service, which routes to the
PostgreSQL primary; the primary streams to a potentially synchronous
standby and a synchronous standby, each with its own
PVC](diagram.png)

- **Storage engine:** OpenBao's native `postgresql` storage backend, with
  `ha_enabled = "true"` for its HA lock table.
- **Database cluster:** a 3-instance CNPG cluster with
  [quorum-based synchronous replication](https://cloudnative-pg.io/docs/current/replication#quorum-based-synchronous-replication)
  (`method: any`, `number: 1`, the default `dataDurability: required`) for
  zero-data-loss failover.
- Workload isolation: node selectors, tolerations and required zonal pod
  anti-affinity keep PostgreSQL on dedicated nodes across separate failure
  domains, following CNPG's
  [scheduling guidance](https://cloudnative-pg.io/docs/current/scheduling).
- **Authentication:** passwordless mTLS via the `DatabaseRole` CRD's
  [`clientCertificate`](https://cloudnative-pg.io/docs/current/declarative_role_management)
  block, for both the schema owner and the application role, enforced by
  explicit `pg_hba` rules.

---

## Step 1: deploy the CNPG cluster, roles and database

The `Cluster` below points `imageCatalogRef` at the
`postgresql-minimal-trixie` `ClusterImageCatalog` that
`REQUIREMENTS_ONLY=true ./demo/setup.sh` already deployed in the previous
step, rather than pinning an image tag directly: CNPG resolves it to the
latest minimal PostgreSQL 18 image in that catalog, so a `kubectl apply`
against the same manifest keeps picking up new patch releases as the
catalog is updated, no `Cluster` edit required. It also declares
synchronous replication, workload isolation, and the two `pg_hba` rules
that force certificate authentication for both roles OpenBao will use. Two
`DatabaseRole` objects follow: `role-openbao`, the schema owner used once
to run DDL, and `role-openbao-rw`, the restricted role OpenBao itself
connects as at runtime. Both get a `clientCertificate`, because a one-shot
DDL job is no more entitled to a password lying around than the
application is.

[`cnpg-stack.yaml`](yaml/cnpg-stack.yaml)

```yaml
{{< include "yaml/cnpg-stack.yaml" >}}
```

Apply these resources:

```bash
kubectl create namespace openbao
kubectl apply -f cnpg-stack.yaml
```

Watch for all three instance pods to come up, which takes a couple of
minutes on a fresh cluster:

```bash
kubectl get pods -w -n openbao
```

Once all three are `Running` and `Ready`, confirm the cluster itself has
reached a healthy state:

```bash
kubectl cnpg -n openbao status openbao-db
```

```text
Cluster Summary
Name                     openbao/openbao-db
System ID:               7674399793927340061
PostgreSQL Image:        ghcr.io/cloudnative-pg/postgresql:18.6-202608131513-minimal-trixie@sha256:e488b1434919f455f2ee4e18a181ce9b33f34cdd8dfb821126855486bce6ad34
Primary instance:        openbao-db-1
Primary promotion time:  2026-08-15 23:10:49 +0000 UTC (3m15s)
Status:                  Cluster in healthy state
Instances:               3
Ready instances:         3
Size:                    135M
Current Write LSN:       0/6000060 (Timeline: 1 - WAL File: 000000010000000000000006)
Continuous Backup not configured
Streaming Replication status
Replication Slots Enabled
Name          Sent LSN   Write LSN  Flush LSN  Replay LSN  Write Lag  Flush Lag  Replay Lag  State      Sync State  Sync Priority  Replication Slot
----          --------   ---------  ---------  ----------  ---------  ---------  ----------  -----      ----------  -------------  ----------------
openbao-db-2  0/6000060  0/6000060  0/6000060  0/6000060   00:00:00   00:00:00   00:00:00    streaming  quorum      1              active
openbao-db-3  0/6000060  0/6000060  0/6000060  0/6000060   00:00:00   00:00:00   00:00:00    streaming  quorum      1              active
Instances status
Name          Current LSN  Replication role  Status  QoS         Manager Version  Node
----          -----------  ----------------  ------  ---         ---------------  ----
openbao-db-1  0/6000060    Primary           OK      BestEffort  1.30.0           k8s-openbao-worker3
openbao-db-2  0/6000060    Standby (sync)    OK      BestEffort  1.30.0           k8s-openbao-worker4
openbao-db-3  0/6000060    Standby (sync)    OK      BestEffort  1.30.0           k8s-openbao-worker5
```

Note the `PostgreSQL Image` line: a SHA-pinned, dated minimal build resolved
straight out of the `postgresql-minimal-trixie` catalog, not a floating tag
we wrote by hand.

Both standbys show up as `Standby (sync)` with a `Sync State` of `quorum` at
the same time, which is exactly the dynamic behaviour `method: any` is meant
to give: with `number: 1`, either standby satisfies durability, and CNPG
does not pin a fixed "the" synchronous standby.

Once reconciled, the operator has created two client certificate secrets,
`role-openbao-client-cert` and `role-openbao-rw-client-cert`, following its
`<databaserole-name>-client-cert` naming convention. `openbao`, as the
database owner, already has `CREATE` on the `public` schema by default
(PostgreSQL grants that to the owner even though it revoked it from `PUBLIC`
in v15), so no extra schema grant is needed before the DDL step.

Every manifest that mounts one of these secrets sets `defaultMode: 0640` on
the volume. Kubernetes mounts `Secret` volumes at `0644` by default, which
`libpq` refuses outright: it rejects a private key file that is
group-or-world-readable, whether owned by root (`0640` or less) or by the
connecting user (`0600` or less). Since the mounted files stay root-owned
and only their group matches the pod's `fsGroup`, `0640` is the setting
that satisfies `libpq` here, and it applies to every pod in this recipe
that reads a client certificate, the schema-init `Job` and the OpenBao
pods alike.

---

## Step 2: initialise the schema and grant table privileges

`DatabaseRole` does not yet manage table-level grants: the `permissions`
stanza that would let a `Database` object express `GRANT`/`REVOKE`
declaratively is still an open proposal
([#10826](https://github.com/cloudnative-pg/cloudnative-pg/issues/10826)),
as I covered when `DatabaseRole` first shipped in
[Recipe 25]({{< relref "../20260706-databaserole-tls-client-certificates/index.md" >}}).
Until that lands, a one-time `Job` running the DDL as the schema owner is the
correct way to create OpenBao's tables and grant the restricted DML the
`openbao-rw` role actually needs.

OpenBao's `postgresql` storage backend expects two tables when
`ha_enabled = "true"`: `openbao_kv_store`, with a `parent_path`, `path`,
`key` and `value` column and a primary key on `(path, key)`, and
`openbao_ha_locks`, holding its HA lock records. Getting the `key` column or
the primary key wrong here is an easy mistake, since OpenBao would otherwise
silently create the table itself on first connection using its own DDL, and
that path only works if the connecting role already has `CREATE`, which
`openbao-rw` deliberately does not. Pre-creating both tables under the owner
role and setting `skip_create_table` on the OpenBao side (Step 3) keeps that
DDL entirely off the restricted runtime role.

The same job also closes a gap PostgreSQL leaves open by default: every
database grants `CONNECT` to `PUBLIC`, and the `public` schema grants
`USAGE` to `PUBLIC` too, so any role that can log into the cluster at all
can connect to `openbao` and see what is in its public schema unless told
otherwise. Making `REVOKE CONNECT ... FROM PUBLIC` the default posture
across every database CloudNativePG manages is on the roadmap
([#10831](https://github.com/cloudnative-pg/cloudnative-pg/issues/10831)),
but it is not there yet, so the schema-init job revokes it explicitly here
and grants back only what `openbao-rw` actually needs:

[`schema-init-job.yaml`](yaml/schema-init-job.yaml)

```yaml
{{< include "yaml/schema-init-job.yaml" >}}
```

Apply the job:

```bash
kubectl apply -f schema-init-job.yaml
```

Wait for its pod to finish `ContainerCreating` and complete before reading
its logs, otherwise `kubectl logs` fails outright rather than waiting:

```bash
kubectl wait --for=condition=complete -n openbao job/openbao-schema-init --timeout=60s
kubectl logs -n openbao job/openbao-schema-init
```

```text
CREATE TABLE
CREATE INDEX
CREATE TABLE
GRANT
REVOKE
GRANT
REVOKE
GRANT
```

Eight statements in, eight confirmations out: both tables, the DML grant,
and the three `REVOKE`/`GRANT` pairs that lock the database and the
`public` schema down to `openbao-rw`.

---

## Step 3: configure and deploy OpenBao via Helm

Configure the official [OpenBao Helm chart](https://github.com/openbao/openbao-helm).
Mount the `role-openbao-rw-client-cert` secret into OpenBao and point the
`postgresql` storage stanza at it with `sslmode=verify-full`. A few details
that are easy to miss from the OpenBao side: `skip_create_table` must be set
explicitly, since `openbao-rw` has no `CREATE` privilege and would otherwise
fail on first connection when OpenBao tries to create the tables itself, and
`server.dataStorage` needs disabling, since it defaults to a 10Gi PVC per pod
that would otherwise sit there unused: the whole point of this stack is that
OpenBao carries no local state at all. Mounting the certificate and CA
secrets also needs the right chart field: `server.extraVolumes` looks like
the obvious choice, but it uses its own simplified `type`/`name`/`path`
schema rather than a raw Kubernetes volume, and there is no matching
`extraVolumeMounts` field for the server `StatefulSet` at all. `server.volumes`
and `server.volumeMounts` are the fields that pass straight through to the
Pod spec, and are what the manifest below actually uses.

[`openbao-values.yaml`](yaml/openbao-values.yaml)

```yaml
{{< include "yaml/openbao-values.yaml" >}}
```

Install OpenBao following the
[official OpenBao Kubernetes documentation](https://openbao.org/docs/platform/k8s/):

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update

helm install openbao openbao/openbao \
  --namespace openbao \
  -f openbao-values.yaml
```

Pod anti-affinity for the OpenBao replicas is not something this recipe has
to configure: the chart's `server.affinity` default already renders a
`requiredDuringSchedulingIgnoredDuringExecution` rule keyed on
`kubernetes.io/hostname`, so the three server pods refuse to land on the
same node. In `cnpg-playground` specifically, that is worth double
checking rather than assuming: with the Postgres nodes tainted and off
limits, only the infra- and app-labelled nodes are left for general
workloads, one short of what three required-anti-affinity replicas need.
The manifest above adds a `server.tolerations` entry for the
`node-role.kubernetes.io/control-plane` taint so OpenBao can use that node
as its third, which is a reasonable thing to do on a single-developer Kind
cluster and not something to carry into a real cluster, where the control
plane should stay clear of ordinary workloads. On a cluster with three or
more untainted worker nodes, the toleration is unnecessary and the chart's
default anti-affinity just works on its own.

---

## Step 4: verification and initialisation

Watch the OpenBao pods come up:

```bash
kubectl get pods -w -n openbao
```

```text
NAME                                      READY   STATUS      RESTARTS   AGE
openbao-0                                 1/1     Running     0          3m11s
openbao-1                                 0/1     Running     0          51s
openbao-agent-injector-84c76c686f-7qnq6   1/1     Running     0          3m11s
openbao-db-1                              1/1     Running     0          8m43s
openbao-db-2                              1/1     Running     0          6m29s
openbao-db-3                              1/1     Running     0          5m48s
openbao-schema-init-x9clq                 0/1     Completed   0          4m7s
```

Only `openbao-0` and `openbao-1` exist so far, and `openbao-1` shows `0/1`:
the `StatefulSet`'s default `OrderedReady` policy will not even create
`openbao-2` until `openbao-1` reports `Ready`, and readiness here is the
unseal status, not just the process being up. That is exactly why the
initialisation and unsealing below has to happen pod by pod, in order:
`openbao-0` first, then `openbao-1`, then `openbao-2`, each one only
created once its predecessor is unsealed.

### Initialise and unseal OpenBao

Initialise the cluster on `openbao-0` and unseal all three pods:

```bash
kubectl exec -it -n openbao openbao-0 -- bao operator init
```

> Store the generated unseal keys and root token securely.

Each pod's Shamir state is independent and in memory: unsealing `openbao-0`
does nothing for `openbao-1` or `openbao-2`, so the same three keys have to
be submitted again, against each pod by name, one pod at a time:

```bash
kubectl exec -it -n openbao openbao-0 -- bao operator unseal <UNSEAL_KEY_1>
kubectl exec -it -n openbao openbao-0 -- bao operator unseal <UNSEAL_KEY_2>
kubectl exec -it -n openbao openbao-0 -- bao operator unseal <UNSEAL_KEY_3>

kubectl exec -it -n openbao openbao-1 -- bao operator unseal <UNSEAL_KEY_1>
kubectl exec -it -n openbao openbao-1 -- bao operator unseal <UNSEAL_KEY_2>
kubectl exec -it -n openbao openbao-1 -- bao operator unseal <UNSEAL_KEY_3>

kubectl exec -it -n openbao openbao-2 -- bao operator unseal <UNSEAL_KEY_1>
kubectl exec -it -n openbao openbao-2 -- bao operator unseal <UNSEAL_KEY_2>
kubectl exec -it -n openbao openbao-2 -- bao operator unseal <UNSEAL_KEY_3>
```

Until a pod's three keys go in, `kubectl describe pod` on it shows
`Unseal Progress: 0/3` and a stream of `Warning Unhealthy` readiness-probe
events. Neither is a problem: it is the probe correctly reporting that the
pod is still sealed, and it clears as soon as that pod gets its keys.

The third key flips `Sealed` to `false`:

```text
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    5
Threshold       3
Version         2.6.1
Commit Date     2026-07-22T14:22:33Z
Storage Type    postgresql
Cluster Name    vault-cluster-97b6aa67
Cluster ID      634fcfcf-09f2-b719-f9bf-1f684cfbe88a
HA Enabled      true
HA Cluster      n/a
HA Mode         standby
```

`Storage Type: postgresql` here is the whole point of this recipe, and it
is not just reporting the config back: OpenBao writes its own bootstrap
state, the keyring, the root key material, its seal configuration, before
you ever create an application secret. Query the cluster directly and it
is already there:

```bash
kubectl cnpg psql -n openbao openbao-db -- openbao
```

```text
openbao=# SELECT key FROM openbao_kv_store;
                                 key
---------------------------------------------------------------------
 keyring
 root-key
 shamir-kek
 seal-config
 barrier-unseal-keys
 info
 jwtkey
 ...
(31 rows)
```

Every one of those rows lives in the `openbao_kv_store` table this
recipe's schema-init `Job` created, written by the `openbao-rw` role with
nothing but a client certificate.

### Read/write test

Confirm OpenBao can write an encrypted payload through to CNPG using the
restricted `openbao-rw` role:

```bash
# Login
kubectl exec -it -n openbao openbao-0 -- bao login <ROOT_TOKEN>

# Enable KV v2 and write a secret
kubectl exec -it -n openbao openbao-0 -- bao secrets enable -path=secret kv-v2
kubectl exec -it -n openbao openbao-0 -- bao kv put secret/test-app username="admin" password="supersecretpassword"

# Read it back
kubectl exec -it -n openbao openbao-0 -- bao kv get secret/test-app
```

Run the same `SELECT key FROM openbao_kv_store;` query again and a new row
for `secret/test-app` shows up alongside the bootstrap keys, its `value`
column holding the payload as an encrypted `BYTEA` blob, never plaintext,
even to someone with direct
[PostgreSQL](https://www.postgresql.org/) access to the table.

Now that all three pods are unsealed, `-o wide` on the whole namespace shows
the full picture: the three CNPG instances on their three dedicated, tainted
Postgres nodes, and the three OpenBao replicas spread across the
control-plane node and the two general-purpose ones, required anti-affinity
satisfied without a single pod colocated with another:

```bash
kubectl get pods -n openbao -o wide
```

```text
NAME                                      READY   STATUS    RESTARTS   AGE   IP           NODE                        NOMINATED NODE   READINESS GATES
openbao-0                                 1/1     Running   0          29m   10.244.3.4   k8s-openbao-worker2         <none>           <none>
openbao-1                                 1/1     Running   0          26m   10.244.2.7   k8s-openbao-worker          <none>           <none>
openbao-2                                 1/1     Running   0          74s   10.244.0.6   k8s-openbao-control-plane   <none>           <none>
openbao-agent-injector-84c76c686f-7qnq6   1/1     Running   0          29m   10.244.2.6   k8s-openbao-worker          <none>           <none>
openbao-db-1                              1/1     Running   0          34m   10.244.5.4   k8s-openbao-worker3         <none>           <none>
openbao-db-2                              1/1     Running   0          32m   10.244.1.4   k8s-openbao-worker4         <none>           <none>
openbao-db-3                              1/1     Running   0          31m   10.244.6.4   k8s-openbao-worker5         <none>           <none>
```

All seven workloads nicely distributed across the six available nodes on
the playground, control plane included, exactly as intended.

---

## Operational notes: certificate renewal

CNPG's client certificates carry a 90-day validity period and are renewed
automatically about a week before expiry, the same schedule the operator
already applies to the `streaming_replica` certificate
(see [Certificates](https://cloudnative-pg.io/docs/current/certificates)).
Renewal replaces the contents of the `role-openbao-rw-client-cert` secret in
place, no manifest change required. Both figures are inherited unconditionally
from the operator's own global settings today; a proposal to let
`clientCertificate` override `duration` and `renewBefore` per `DatabaseRole`,
mirroring cert-manager's convention, is open in
[issue #11312](https://github.com/cloudnative-pg/cloudnative-pg/issues/11312),
useful if a role like `role-openbao-rw` ever needs a renewal cadence
different from the cluster-wide default.

OpenBao itself does not pick that renewal up on its own. Like Vault before
it, OpenBao's `postgresql` storage backend opens its connection pool once at
process startup and never re-reads the certificate files afterwards, so a
renewed certificate only takes effect after a rolling restart of the OpenBao
pods. This is a property of the storage plugin's own connection lifecycle,
not something CNPG's certificate reconciliation controls: CNPG's job ends at
keeping the secret current, and nothing on the CNPG side requires a restart.
Until OpenBao's storage backend gains a way to reload its connection pool's
TLS material on signal, budget for a scheduled rolling restart inside the
83-day renewal window, well before the old certificate actually expires.

---

## Beyond this setup: backups and disaster recovery

This is a single-cluster deployment. High availability inside the Kubernetes
cluster is covered by the three OpenBao replicas, CNPG's synchronous
replication and required zonal anti-affinity, but production workloads need
more than that:

- **Automated PostgreSQL backups:** the in-tree `.spec.backup.barmanObjectStore`
  stanza is deprecated as of CNPG 1.26 in favour of the
  [Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/): define
  an `ObjectStore` pointing at AWS S3, Google Cloud Storage or Azure Blob
  Storage, reference it from the `Cluster`'s `.spec.plugins`, and back it with
  `Backup`/`ScheduledBackup` resources using `method: plugin` for continuous
  WAL archiving and scheduled base backups, enabling Point-In-Time Recovery.
- **Disaster recovery:** to meet real RTO/RPO targets, span the deployment
  across more than one Kubernetes cluster. CNPG's
  [distributed topology](https://cloudnative-pg.io/docs/current/replica_cluster#distributed-topology)
  lets an asynchronous replica cluster in a second region or cluster promote
  to primary if the first one is lost entirely, the same capability I
  discussed for
  [cloud-neutral portability]({{< relref "../20260414-dbaas-trap-sovereignty/index.md" >}}).

---

## Conclusion

Combining OpenBao with CloudNativePG gives you a fully open-source,
enterprise-grade secrets engine running on native
[Kubernetes](https://kubernetes.io/) CRDs, with the `DatabaseRole` CRD
covering every role in the stack rather than just the application-facing
one. Synchronous replication gives zero-data-loss failover, explicit
`pg_hba` rules turn the absence of a password into an actual enforced
policy rather than an assumption, and dedicated scheduling rules keep the
database's failure domains separate from everything else running in the
cluster.

If you have ideas, questions, or run into something this recipe does not
cover, reach out to Rob and me directly on LinkedIn, or find us on the
CloudNativePG community's
[CNCF Slack](https://github.com/cloudnative-pg/cloudnative-pg#getting-in-touch).

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_This article was drafted and refined with the assistance of Claude
(Anthropic). All technical content, corrections and editorial direction are
the author's own._

<!--
_Cover Picture: TODO - add cover.png/thumb.png and this attribution before
publishing._
-->
