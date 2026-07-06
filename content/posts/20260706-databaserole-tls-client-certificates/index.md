---
title: "CNPG Recipe 25 - Declarative Roles and Passwordless TLS in CloudNativePG 1.30"
date: 2026-07-06T18:56:47+10:00
description: "How CloudNativePG 1.30's DatabaseRole CRD and built-in client
  certificates let app teams own PostgreSQL credentials without touching the
  Cluster manifest."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg",
  "dok", "data on kubernetes", "databaserole", "roles", "tls", "mtls",
  "certificates", "cert-authentication", "security", "gitops", "rbac",
  "high-availability", "operator", "declarative-configuration",
  "separation-of-concerns"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_CloudNativePG 1.30 introduces the `DatabaseRole` CRD and built-in TLS client
certificate issuance, letting application teams own their PostgreSQL
credentials declaratively and connect without ever handling a password._

<!--more-->

---

[CloudNativePG 1.30](https://cloudnative-pg.io/releases/cloudnative-pg-1-30.0-released/)
shipped last week, and alongside a Lease-based primary election
primitive and a batch of security hardening (`search_path` pinning, SCRAM
password encoding, authenticated operator-to-instance communication) it
quietly closed a gap that has bothered me for a while: PostgreSQL roles had
never had the standalone API treatment that databases already got. This
post is about the two changes that fix that, and why I think they matter
more than their line count in the release notes suggests.

Roles matter to me because of where they used to live: bolted onto the
`Cluster` spec, the one object a platform team should never have to hand out
write access to just so an application team can manage its own credentials.
Version 1.30 finally gives roles
[an object of their own](https://cloudnative-pg.io/docs/current/declarative_role_management#the-databaserole-resource).

## Why roles deserved their own resource

PostgreSQL has three genuinely global objects that sit outside any single
database's own catalog: roles (`pg_authid`), databases (`pg_database`) and
tablespaces (`pg_tablespace`), all shared across the whole instance. A
tablespace, though, is not just an entry in that shared catalog: it is a
live pointer to a directory on a filesystem that every instance has to
mount, so the operator has no way to reason about it without also reasoning
about storage, volumes and instances, which is exactly what the `Cluster`
spec already does. Roles and databases carry no such physical dependency,
yet roles remained bolted onto the `Cluster` spec while databases had
already been split out into their own CRD. With `DatabaseRole`, roles
finally join `Database` in getting their own CRD and their own
reconciliation loop, which is a real improvement on both ends: a cleaner
surface for GitOps and RBAC on the user side, and a simpler, more focused
reconciler on the operator side instead of one controller keeping storage,
replication and an arbitrary list of roles all in sync at once.

For a long time, CloudNativePG has supported declarative role management
through the `managed.roles` stanza inside the `Cluster` spec. It works, but
it has an architectural flaw: every role, whether it belongs to a platform
concern like monitoring or to a specific application, lives inside the same
object that defines storage, replicas, backups and failover behaviour.
Granting an application team the ability to add a role to `managed.roles`
means granting them write access to the `Cluster` itself, and Kubernetes
RBAC has no way to scope that down to a single field in a spec.

The new `DatabaseRole` CRD (see the
[Role management](https://cloudnative-pg.io/docs/current/declarative_role_management#the-databaserole-resource)
docs) turns a role into a standalone, namespaced Kubernetes object with its
own lifecycle, its own `status` and its own RBAC surface. A platform team
can grant an application team `create`/`update` on
`databaseroles.postgresql.cnpg.io` scoped to their namespace, and nothing
more. The application team gets full control over the roles their workload
needs, without ever seeing, let alone editing, the `Cluster` resource. That
is the separation of concerns principle actually enforced by the Kubernetes
API server, not just by convention or code review discipline.

For any new role, I would reach for `DatabaseRole` over `managed.roles` by
default now. There is no functional regression in doing so, and the RBAC and
lifecycle benefits above apply from the first role you declare, not just
once you have many.

The two approaches coexist. You can migrate a role from `managed.roles` to a
`DatabaseRole` incrementally, cluster by cluster or role by role, and if a
name exists in both places the `Cluster` spec wins, with the conflict surfaced
in the `DatabaseRole` status rather than failing silently. Removal also
differs: `managed.roles` uses the `ensure: absent` field, while a
`DatabaseRole` expresses intent through `databaseRoleReclaimPolicy`, set to
`retain` (the safe default, mirroring how `PersistentVolumes` behave) or
`delete`, which issues `DROP ROLE` when the resource is deleted. Worth
noting: pointing a `DatabaseRole` at a role that already exists in the
database adopts it, resetting every omitted attribute to its PostgreSQL
default, so review the role's current state before you do that.

There is also a very concrete driver behind this, not just architectural
tidiness. `DatabaseRole` is a requirement for a capability we want next:
bootstrapping a genuinely empty cluster, one that does not create a default
`app` user and `app` database at all
([#3242](https://github.com/cloudnative-pg/cloudnative-pg/issues/3242)).
Today, as the worked example later in this post shows, `Cluster` bootstrap
always creates that default identity by convention. Decoupling role and
database management from the `Cluster` spec is the precondition for letting
an empty cluster exist with no identities baked in, leaving `DatabaseRole`
and `Database` objects as the sole source of truth from the very first
reconcile.

## Passwordless connections with TLS client certificates

The second piece is the one I find genuinely exciting: a `DatabaseRole` can
carry a `clientCertificate` block, and the operator will generate and
continuously renew a TLS client certificate for that role, signed by the
cluster's client CA, and store it in a `<databaserole-name>-client-cert`
`Secret` alongside the usual `tls.crt` and `tls.key` keys.

This matters because CloudNativePG, in its default operator-managed mode,
already maintains a single self-signed CA used for both server and client
certificates (see the
[Certificates](https://cloudnative-pg.io/docs/current/certificates)
page), and already uses that CA to issue the `streaming_replica` client
certificate for physical replication. It even already ships a
`kubectl cnpg certificate` command that signs a client certificate for any
role from that same CA. What was missing was declarative management of that
certificate. `kubectl cnpg certificate` is imperative: you run it once, it
hands you a `Secret`, and from that point the certificate is on its own.
Nothing re-runs the command before the 90-day validity window closes, and
nothing deletes the `Secret` when the role goes away, so both jobs land back
on whoever remembers to script them. `clientCertificate` on a `DatabaseRole`
makes the certificate part of the role's declared state instead of a
one-time side effect: the operator renews it on the same schedule it already
applies to `streaming_replica`, and removes the `Secret` automatically when
you disable the feature or delete the role.

`login: true` is mandatory when `clientCertificate` is enabled: the operator
validates this at admission and rejects the resource otherwise, which is a
sensible guard rail since a certificate for a role that cannot log in is
just dead weight.

## A worked example

Here is a minimal set of manifests inspired by the testing I did against the
[pull request that implemented the feature](https://github.com/cloudnative-pg/cloudnative-pg/pull/10896).
It deploys a three-instance cluster, a `Database` object owned by a role
called `app` and a `DatabaseRole` for that same role with certificate
issuance switched on:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: angus
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-minimal-trixie
  postgresql:
    pg_hba:
      - hostssl app app all cert
      - hostnossl app app all reject
  storage:
    size: 1Gi
---
apiVersion: postgresql.cnpg.io/v1
kind: DatabaseRole
metadata:
  name: angus-app
spec:
  cluster:
    name: angus
  name: app
  login: true
  clientCertificate:
    enabled: true
  databaseRoleReclaimPolicy: delete
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: angus-app
spec:
  cluster:
    name: angus
  name: app
  owner: app
  databaseReclaimPolicy: delete
```

The role and the database are both called `app` here simply to match
CloudNativePG's own bootstrap convention (more on that below), not because
either name is required. Pick whatever suits your workload, and declare as
many `DatabaseRole` and `Database` objects as you need, each with its own
name, its own certificate and its own reclaim policy.

The `pg_hba` entries are doing the real enforcement work, and they need to,
because `app` is not actually passwordless today. CloudNativePG's own
convention-over-configuration default already creates an `app` database
owned by an `app` role with a randomly generated password, stored in a
`<cluster-name>-app` `Secret`, independently of anything our `Database` and
`DatabaseRole` declare. `hostssl app app all cert` tells PostgreSQL that a
TLS connection for `app` to the `app` database must authenticate with a
certificate, full stop, but on its own it says nothing about a plaintext
connection. `hostnossl app app all reject` closes that gap explicitly:
without it, a plaintext connection for `app` would fall through to the
cluster's default `scram-sha-256` rule and succeed, using the very password
this whole exercise is meant to route around. Making that a hard `reject` is
what actually enforces "TLS and a certificate, always", rather than relying
on the password not existing. Removing that bootstrap-generated password
from the picture entirely is on the roadmap for a future CloudNativePG
release; today, the explicit `reject` is what stands in its place.

A couple of other details worth calling out:

- Notice there is no `passwordSecret` anywhere in the `DatabaseRole`. Our own
  objects never set or manage a password for `app`, so nothing we declare
  adds to the attack surface, nothing we declare needs rotating and nothing
  we declare is exposed to
  [CVE-2026-55765](https://github.com/cloudnative-pg/cloudnative-pg/security/advisories/GHSA-w3gf-xc94-wvmj)-style
  issues. The bootstrap-generated password above is the one loose end, and
  it is the cluster's doing, not the role's.
- I set both `databaseRoleReclaimPolicy` and `databaseReclaimPolicy` to
  `delete` rather than leaving them at their `retain` default. This is a
  personal preference, not just a test-cluster shortcut: if a role or a
  database is declared through a manifest, I want deleting that manifest to
  actually delete the object in PostgreSQL. `retain` has its place when a
  human, not a controller, is expected to make the final call on dropping
  something, but for anything owned end to end by GitOps I would rather the
  cluster state matched the repository state exactly.

### Inspecting the generated `pg_hba.conf`

Before touching certificates, it is worth seeing where our rule actually
lands. CloudNativePG builds `pg_hba.conf` from a fixed-rules section, a
user-defined section (ours) and a default section, in that order (see the
[PostgreSQL Configuration](https://cloudnative-pg.io/docs/current/postgresql_conf#the-pg_hba-section)
docs). The `kubectl cnpg` plugin surfaces the generated file directly, with
those sections labelled, so there is no need to exec into a pod for it:

```bash
kubectl cnpg status angus -vv
```

Which, among other things, displays the following output:

```text
PostgreSQL HBA Rules
#
# FIXED RULES
#
# Grant local access ('local' user map)
local all cnpg_metrics_exporter peer map=cnpg_metrics_exporter
local all all peer map=local
# Require client certificate authentication for the streaming_replica user
hostssl postgres streaming_replica all cert map=cnpg_streaming_replica
hostssl replication streaming_replica all cert map=cnpg_streaming_replica
hostssl all cnpg_pooler_pgbouncer all cert map=cnpg_pooler_pgbouncer
#
# USER-DEFINED RULES
#
hostssl app app all cert
hostnossl app app all reject
#
# DEFAULT RULES
#
host all all all scram-sha-256
```

Our two lines land exactly where declared, under `USER-DEFINED RULES`,
between the operator's fixed, non-negotiable rules (`streaming_replica`, the
metrics exporter, the PgBouncer pooler user) and the default catch-all at
the bottom. Because `pg_hba.conf` is evaluated top to bottom and the first
match wins, an SSL connection for `app` is forced through `cert`
authentication, and a plaintext one is rejected outright, no matter what the
default rule at the end says.

### Connecting without a password

Once the cluster is `Cluster in healthy state` and the `DatabaseRole` reports
`applied: true`, the operator has created the `angus-app-client-cert` `Secret`:

```bash
kubectl get secret angus-app-client-cert -o jsonpath='{.type}'
# kubernetes.io/tls
```

The certificate and its private key live in that `Secret`, and the whole
point of `cert` authentication is that the private key never has to leave
the cluster. So rather than pulling it down to a laptop, I connect from a
Pod that mounts the two `Secret`s it needs directly. This is deliberate: it
simulates an application running in the same namespace as its database,
which is the microservice database pattern CloudNativePG is built around,
rather than a client connecting in from outside the cluster:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: psql-cert-client
spec:
  restartPolicy: Always
  securityContext:
    runAsNonRoot: true
    runAsUser: 26
    fsGroup: 26
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: client-cert
      secret:
        secretName: angus-app-client-cert
        defaultMode: 0640
    - name: client-ca
      secret:
        secretName: angus-ca
        defaultMode: 0640
  containers:
    - name: psql
      image: ghcr.io/cloudnative-pg/postgresql:18.4-minimal-trixie
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: client-cert
          mountPath: /etc/secrets/tls
          readOnly: true
        - name: client-ca
          mountPath: /etc/secrets/ca
          readOnly: true
      env:
        - name: PGHOST
          value: angus-rw
        - name: PGPORT
          value: "5432"
        - name: PGDATABASE
          value: app
        - name: PGUSER
          value: app
        - name: PGSSLMODE
          value: verify-full
        - name: PGSSLCERT
          value: /etc/secrets/tls/tls.crt
        - name: PGSSLKEY
          value: /etc/secrets/tls/tls.key
        - name: PGSSLROOTCERT
          value: /etc/secrets/ca/ca.crt
        - name: HOME
          value: /tmp
      command: ["sleep", "infinity"]
```

With the Pod running, `psql` connects with no password prompt and no
argument beyond the command itself:

```bash
kubectl exec -it pod/psql-cert-client -- \
  psql -c 'SELECT * FROM pg_stat_ssl'
```

```text
 pid | ssl | version | cipher                  | bits | client_dn | client_serial                            | issuer_dn
-----+-----+---------+-------------------------+------+-----------+------------------------------------------+-------------------
 756 | t   | TLSv1.3 | TLS_AES_256_GCM_SHA384  |  256 | /CN=app   | 203360611089765729748366787124077718131  | /OU=default/CN=angus
```

`client_dn` confirms PostgreSQL authenticated the connection as `app` purely
from the certificate's subject, and `issuer_dn` confirms it was signed by
our cluster's own CA. If the certificate's common name did not match `app`,
or if the role had its login privilege revoked, PostgreSQL would reject the
connection at the TLS handshake stage rather than falling through to a
password prompt. That is exactly the behaviour `hostssl ... cert` is meant
to give you.

## Why this combination is the interesting part

Individually, declarative roles and client certificate issuance are both
useful. Together with the `Database` CRD (already declarative since earlier
releases), they close a loop I have wanted closed for a long time: an
application team can now onboard a new workload with three manifests, none
of which touch the `Cluster`, none of which contain a password and all of
which are ordinary GitOps artefacts that a controller can reconcile, diff and
audit like anything else in the cluster.

This is not just tidiness. Every password you remove from the system is an
attack surface you no longer have to defend, a `Secret` you no longer have
to rotate on a schedule and a credential that cannot leak through a
misconfigured log line or an over-permissioned Kubernetes RBAC role that
grants read on `Secret`s. Combined with the `search_path` pinning and SCRAM
encoding fixes in the same release, 1.30 reads to me like a release that
took an honest look at the credential lifecycle end to end, not just at the
role CRUD API.

## The rest of 1.30, briefly

I focused on roles and certificates because they are the pieces I tested
directly, but the release has more worth knowing about: a `Lease`-based
primary election primitive that serialises promotion without waiting out the
full failover timeout, in-place major upgrades for clusters using Image
Volume extensions, `Pooler` image management through Image Catalogs, TLS for
the `Pooler` metrics endpoint and a `PrimaryStatusCheckFailed` event that
finally surfaces a specific class of failover deferral that used to be
invisible until someone went digging through logs. The full list is in the
[release announcement](https://cloudnative-pg.io/releases/cloudnative-pg-1-30.0-released/)
and the
[1.30 release notes](https://cloudnative-pg.io/docs/current/release_notes/v1.30/).

One API change to plan around: the `cluster` reference on `Database`,
`Pooler`, `Publication`, `Subscription` and `ScheduledBackup` is now
immutable, enforced by a CEL validation rule at the API server. Re-pointing
one of these resources at a different cluster never had well-defined
semantics, and now it is rejected rather than silently doing something you
did not intend.

## The job isn't finished

`DatabaseRole` and `Database` now cover identity and existence: who a role
is, what it can authenticate as and which databases exist. What they don't
cover yet is the privilege surface underneath, and that gap is the next
thing we are working on, targeting the 1.31 milestone:

- [#10826](https://github.com/cloudnative-pg/cloudnative-pg/issues/10826)
  proposes a `permissions` stanza on the `Database` CRD for database-level
  `GRANT`/`REVOKE`, using the same explicit `{name, type: grant|revoke}`
  shape already merged for FDW and foreign server usage. The headline case
  is `REVOKE CONNECT ON DATABASE x FROM PUBLIC`: PostgreSQL grants `CONNECT`
  and `TEMPORARY` to `PUBLIC` by default, so almost every production setup
  has to claw that back by hand today.
- [#7872](https://github.com/cloudnative-pg/cloudnative-pg/issues/7872) does
  the equivalent one level down, adding `CREATE` and `USAGE` grants
  alongside the existing `owner` field on a `Database`'s `schemas` stanza.
- [#10831](https://github.com/cloudnative-pg/cloudnative-pg/issues/10831)
  builds on both to make "revoke `CONNECT` from `PUBLIC`" the default
  posture across every database CloudNativePG manages: the `postgres`
  maintenance database, the bootstrapped application database and any
  `Database` CRD object alike. It has to land opt-in first: flipping
  PostgreSQL's open-by-default connection model unconditionally would break
  workloads that rely on it, so this is a deprecation window, not a
  same-release switch.

That is deliberately where the scope stops. CloudNativePG manages
global and schema-level objects: roles, databases, tablespaces and now the
grants that sit on top of them. It has no intention of reaching further down
into individual tables, views or other schema-scoped objects. That is the
job of schema migration tools such as
[Atlas](https://atlasgo.io/integrations/kubernetes/quickstart) or
[SchemaHero](https://schemahero.io/), and duplicating
it inside the operator would blur a boundary that already works well.

Once those three land, CloudNativePG will own the full declarative path from
"this role exists" through to "this is exactly what it is allowed to touch,
down to the schema", with no post-init SQL script standing in the gap. That
is the standard I think a Kubernetes-native Postgres operator should be held
to, and roles and certificates in 1.30 are the foundation it is built on,
not the finish line.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_This article was drafted and refined with the assistance of Claude (Anthropic).
All technical content, corrections and editorial direction are the author's own._

_Cover Picture: ["Asian Elephant"](https://animalia.bio/asian-elephant)._
