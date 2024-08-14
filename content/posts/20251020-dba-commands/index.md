---
title: "Postgres in Kubernetes: the commands every DBA should know"
date: 2025-10-21T08:18:49+03:00
description: "This article guides PostgreSQL DBAs through the essential `kubectl` commands that directly translate traditional database management tasks into the Kubernetes environment, fostering confidence in cloud-native Postgres."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "dok", "data on kubernetes", "dba", "postgres operator", "cloud native", "kubectl"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_For many Postgres DBAs, Kubernetes feels like a new, complex world. But what
if your existing skills were the key to unlocking it? This article demystifies
cloud-native Postgres by revealing a first handful of `kubectl` and `kubectl
cnpg` commands that act as your direct translator.
I'll move past the intimidating YAML to focus on the practical, imperative
commands you'll actually use to troubleshoot, inspect, and even perform a
production switchover. You'll see how your core DBA work maps directly to this
new environment, helping you build the confidence to take the next step into
the cloud-native world._

<!--more-->

---

This year’s Postgres European conference in Prague is preceded by the first
[PostgreSQL on Kubernetes summit](https://www.postgresql.eu/events/pgconfeu2025/schedule/session/7150-postgresql-on-kubernetes-summit/)
as part of the community events day.
I will be having a short presentation entitled “Postgres in Kubernetes: the
commands every DBA should know”, focused on CloudNativePG. This blog article
serves as the transcript for that demo, walking through the essential commands.

The most important 'command' a DBA must learn when approaching Kubernetes isn't
a command at all—it's a **mindset shift**. We move from a *mutable* and
*imperative* world (where we log in and change things) to a *declarative* one
(where we describe the desired state). With an operator like CloudNativePG
managing your high-availability Postgres clusters, your primary job becomes
defining that state in YAML manifests. You'll work with CloudNativePG resources
like `Cluster` and `Pooler`, which in turn manage core Kubernetes objects like
`Pods`, `Services`, and `PersistentVolumeClaims`.

**But that doesn't mean commands disappear**. You will absolutely need them for
day-to-day operations: verifying the cluster's health, connecting for ad-hoc
queries, and especially troubleshooting issues.

A quick but important note: all the commands we'll discuss require the correct
[RBAC (Role-Based Access Control)](https://cloudnative-pg.io/documentation/current/security/#role-based-access-control-rbac)
permissions in your Kubernetes environment.
Before you start, work with your infrastructure team to ensure you have the
necessary access. Beware that some of them might only work in your learning
environment, as most likely you will not be granted access to run them in
production (but you might be asked to help your administrators in the
resolution of problems).

In order to follow this article, you need to have access to a Kubernetes
cluster, and you need to have the CloudNativePG operator installed in it.
If you want to practise and learn, my advice is to follow my
["CloudNativePG Recipe 1"]({{< relref "../20240303-recipe-local-setup/index.md" >}})
or simply deploy the [CNPG Playground](https://github.com/cloudnative-pg/cnpg-playground).

With that foundation set, let's dive into the live commands.

-----

## The DBA's new toolkit: `kubectl`

All the commands we'll see are based on `kubectl`, the command-line tool for
Kubernetes. Think of it as your new `psql`, `ssh`, and `systemctl` all rolled
into one. We'll use `kubectl` to interact with standard Kubernetes resources
and, more importantly, with the [CloudNativePG plugin](https://cloudnative-pg.io/documentation/current/kubectl-plugin/).
This plugin, invoked as `kubectl cnpg`, is the official command-line interface
for CloudNativePG and provides all our DBA-specific commands.
As maintainers, we recommend every CloudNativePG user to install it.

## Step 0: Check your environment

Before you do anything, you need to know where you are.

First, check which Kubernetes cluster your `kubectl` is pointing to:

```bash
kubectl config current-context
```

Next, see the physical (or virtual) machines that make up your cluster:

```bash
kubectl get nodes
```

Finally, let's verify that the CloudNativePG operator itself is running. The
operator is just another application in Kubernetes, typically in its own
namespace (like `cnpg-system`).

```bash
# Check the operator pods in the 'cnpg-system' namespace
kubectl get pods -n cnpg-system -o wide
```

You should see a pod for the `cnpg-controller-manager` in a `Running` state.
If this isn't running, none of the database commands will work.

Once you know the operator is running, you can verify that its custom resources
(CRDs) are registered with Kubernetes using `kubectl explain`:

```bash
kubectl explain clusters.postgresql.cnpg.io
```

This command proves the `Cluster` resource is available and also acts as your
built-in documentation for all available fields.

## Step 1: Create a Postgres cluster

Now, the declarative part. We'll define our cluster in a YAML file. Let's call
it `jimi.yaml`. Note that we are requesting a separate volume for WALs using
`walStorage`.

```yaml
{{< include "yaml/jimi.yaml" >}}
```

We deploy it with `kubectl apply`:

```bash
kubectl apply -f jimi.yaml
```

This command tells Kubernetes: "Make the world look like this file." The
operator picks up this request and starts building our cluster.

## Step 2: "Is my database running?" (High-Level)

To see the high-level status, we ask for the `Cluster` resource we just
created. The `describe` command gives you a very detailed, multi-section view,
which is great for deep troubleshooting:

```bash
kubectl describe cluster jimi
```

Alternatively and more succinctly, you can use the `get` command for a clean,
one-line summary:

```bash
kubectl get cluster jimi
```

This gives the main dashboard view:

```
NAME   AGE     INSTANCES   READY   STATUS                     PRIMARY
jimi   2m30s   3           3       Cluster in healthy state   jimi-1
```

This shows our 3-node cluster is healthy and `jimi-1` is the primary.

To see the *full* declarative state (every setting, all the defaults the
operator applied, and the current status), you can get the resource as YAML:

```bash
kubectl get -o yaml cluster jimi
```

This is your "single source of truth" and is essential for troubleshooting.

## Step 3: Familiarise with cluster components

The operator instantiated our `jimi` cluster by creating several *standard*
Kubernetes resources. As a DBA, you need to know what these are
(you might find interesting my article
["The urge of 'T-shaped' profiles to smooth the challenges of running Postgres in Kubernetes"]({{< relref "../20240812-tshaped/index.md" >}})).

They are all tied together using **label selectors** (you can find a complete
reference for all labels and annotations used by CloudNativePG in the
[official documentation](https://cloudnative-pg.io/documentation/current/labels_annotations/)).

- **Pods:** these are the running Postgres instances.
  ```bash
  kubectl get pods -o wide -l cnpg.io/cluster=jimi
  ```

- **Services:** these are the stable network endpoints for your app.
  ```bash
  kubectl get service,endpoints -l cnpg.io/cluster=jimi
  ```
  You'll see `jimi-rw` (for the primary), `jimi-ro` (for replicas), and
 `jimi-r` (for any instance).

- **PVCs (PersistentVolumeClaims):** this is your storage.
  ```bash
  kubectl get pvc -l cnpg.io/cluster=jimi  `
  ```
  You'll see one PVC for `PGDATA` and one for `WAL` *per instance*.

- **Secrets & ConfigMaps:** these hold generated credentials and configuration
  data.
  ```bash
  kubectl get secrets,configmaps -l cnpg.io/cluster=jimi
  ```
  For example, if you install the `view-secret` plugin, you can easily inspect the credentials for the default `app` user:
  ```bash
  $ kubectl view-secret jimi-app
  ┃ Secret Data
  ┃ Found 11 keys in secret "jimi-app". Choose one or select 'all' to view.
  ┃ > password
  ...
  ```
- **PDB (PodDisruptionBudget):** this tells Kubernetes how to safely perform maintenance (e.g., "never take down the primary and a replica at the same time").
  ```bash
  kubectl get pdb -l cnpg.io/cluster=jimi
  ```

## Step 4: "How is replication?" (DBA-specific)

For a detailed, Postgres-specific status, use the `cnpg` plugin:

```bash
kubectl cnpg status jimi
```

This command returns a rich, DBA-friendly status report with LSNs, replication
lag, and sync status. Running this is powerful, so your user will need
sufficient RBAC permissions, including rights to `get` clusters, `list` pods
and PDBs, `create` pod execs/proxies, and `get` Barman Cloud object stores for
backup status.

## Step 5: "How do I change a setting (or update Postgres)?"

In a traditional VM, you would edit `postgresql.conf` and then reload the
service. In Kubernetes, you change the *source of truth*—the `Cluster`
manifest.

### Changing Configuration

The best practice, especially in a team or CI/CD pipeline, is to modify your
local `jimi.yaml` file (e.g., add a `postgresql` section to change
`max_connections`) and re-apply it:

```bash
kubectl apply -f jimi.yaml
```

However, for a quick, on-the-fly change during development or troubleshooting,
you can edit the *live* cluster definition directly in Kubernetes:

```bash
kubectl edit cluster jimi
```

This command opens the cluster's YAML definition in your default text editor.
When you save and exit, Kubernetes applies the changes immediately. In either
case, the CloudNativePG operator will detect the change and, if necessary,
automatically perform a rolling restart of the pods to apply the new
configuration.

### Updating PostgreSQL

This same declarative logic applies to PostgreSQL updates. In a VM, you
would run `apt update` or `yum update` to get a new minor version.
Here, you simply update the cluster's manifest with a new container image tag.

For example, to update from `postgresql:18-minimal-trixie` to a newer version,
you would just change the `imageName` field in your YAML and `kubectl apply` it
(or use `kubectl edit cluster jimi`):

```yaml
...
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-minimal-trixie # Changed this line
...
```

The operator will then safely perform a rolling update of your cluster, one
instance at a time, ensuring the primary is the last to be updated.
For managing updates across many clusters (especially major versions),
CloudNativePG provides a more advanced feature called image catalog, which you
can read about in ["CloudNativePG Recipe 22"]({{< relref "../20251006-image-catalog/index.md" >}}).

## Step 6: "Let me in!" (connecting with `psql`)

To get a `psql` shell on the *primary* instance, the plugin makes it simple:

```bash
kubectl cnpg psql jimi
```

How does this work? It's not magic, it's `kubectl exec`. The plugin finds the
correct primary pod for the `jimi` cluster and then runs the `psql` client
*inside* that pod's container.

It's important to remember that this is for administrative and
troubleshooting access only, not for your applications.
Your applications should always connect through the Kubernetes `Service` (e.g.,
`jimi-rw`), running from their own pods, typically within the same Kubernetes
cluster.

This direct `exec` action requires specific RBAC permissions for the DBA's
user account: namely, the ability to `get` and `list` pods (to find the
primary) and to `create` a `pods/exec` session (to run `psql` inside it).

## Step 7: "Where are the logs?"

You don't `tail -f` a file anymore. In Kubernetes, logs go to standard output.
While you can use `kubectl logs <pod-name>`, the `cnpg` plugin has a better
way: it can stream logs from *all* instances at once and "pretty-print" the
JSON output into a human-readable format.

```bash
# Stream logs from all instances and make them readable
kubectl cnpg logs cluster jimi -f | kubectl cnpg logs pretty
```

This is incredibly powerful for watching replication or troubleshooting an
issue across the whole cluster.

## Step 8: Switching over

Finally, a planned and controlled switchover of the primary (an automatic
failover is what happens when a node dies). Instead of Patroni or repmgr, you
use the `cnpg promote` command:

```bash
# Promote the pod 'jimi-2' to be the new primary
kubectl cnpg promote jimi jimi-2
```

This plugin command is a convenient wrapper. All it does underneath is patch
the `Cluster`'s status to declare your new intent to the operator:

```bash
# This is what 'cnpg promote' does for you
kubectl patch cluster jimi --type=merge --subresource=status \
  -p '{"status": {"targetPrimary": "jimi-2"}}'
```

The operator performs a graceful switchover by orchestrating Kubernetes labels.
The `jimi-rw` Service is not modified; it simply targets the pod with the
`cnpg.io/instanceRole: primary` label. The `promote` command orchestrates
removing this label from the old primary, promoting the replica, applying the
label to the new primary once it's ready, and reconfiguring all other standbys
to follow it.

## Summary table

Here is a quick reference table of all the commands I covered in the article:

| DBA Task / Traditional Command | Cloud-Native Command (Kubernetes / `cnpg` plugin) |
| :--- | :--- |
| **Environment Check** | |
| "Which cluster am I on?" | `kubectl config current-context` |
| "What machines are in this cluster?" | `kubectl get nodes` |
| "Is the Postgres Operator running?" | `kubectl get pods -n cnpg-system -o wide` |
| "Is the `Cluster` resource available? What are its fields?" | `kubectl explain clusters.postgresql.cnpg.io` |
| **Cluster Lifecycle & Configuration** | |
| Install / Configure Postgres | `kubectl apply -f jimi.yaml` |
| "Is Postgres running?" (High-Level) | `kubectl get cluster jimi` |
| "Show me a detailed status." | `kubectl describe cluster jimi` |
| "Show me *every* setting (the source of truth)." | `kubectl get -o yaml cluster jimi` |
| Edit `postgresql.conf` & reload (for a quick change) | `kubectl edit cluster jimi` |
| Edit `postgresql.conf` & reload (GitOps/file-based) | `kubectl apply -f jimi.yaml` |
| **Inspecting Cluster Components** | |
| "Show me the Postgres processes." (`ps aux \| grep`) | `kubectl get pods -o wide -l cnpg.io/cluster=jimi` |
| "Where's my data directory?" (`df -h`) | `kubectl get pvc -l cnpg.io/cluster=jimi` |
| "What are the DB connection IPs/DNS names?" | `kubectl get service,endpoints -l cnpg.io/cluster=jimi` |
| "Show me HA/maintenance safety rules." | `kubectl get pdb -l cnpg.io/cluster=jimi` |
| "Show me the auto-generated passwords/configs." | `kubectl get secrets,configmaps -l cnpg.io/cluster=jimi`|
| **DBA Operational Commands** | |
| Check replication status (`SELECT * FROM pg_stat_replication;`)| `kubectl cnpg status jimi` |
| Connect to the primary (`psql -h <ip>`) | `kubectl cnpg psql jimi` |
| Follow the logs (`tail -f postgresql.log`) | `kubectl cnpg logs cluster jimi -f \| kubectl cnpg logs pretty` |
| Perform a switchover (`patronictl switchover`) | `kubectl cnpg promote jimi <replica-pod-name>` |


## Conclusion

As you can see, the *tasks* of a DBA don't change in Kubernetes. You still need
to check status, connect, read logs, monitor replication, and manage
**switchovers**. What changes is the *tooling*.

In this article, I focused almost entirely on the `Cluster` resource, but this is
just the beginning. For time reasons, I couldn't cover other critical topics
like backups and observability. CloudNativePG provides a rich set of Custom
Resources for managing your database declaratively, including `Backup`,
`ScheduledBackup`, `Pooler`, `Database`, `Publication`, `Subscription`,
`ClusterImageCatalog`, and `ImageCatalog`.

For observability, there's even less to *do*, as you only need to understand
that CloudNativePG automatically provides a metrics exporter for Prometheus
right out of the box.

By moving from an imperative `systemctl` world to a declarative, YAML-driven
one, you let the operator handle the repetitive, complex work. Your job is to
tell the operator what you *want*. And when you need to check on its work or
take manual control, `kubectl` and the `kubectl cnpg` plugin are your new,
powerful set of tools.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

<!--
_Cover Picture: [“TITLE“](URL)._
-->

