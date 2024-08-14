---
title: "CloudNativePG Recipe 11 - Isolating PostgreSQL Workloads in Kubernetes with Kind"
date: 2024-08-16T13:46:57+02:00
description: "This article provides a step-by-step guide on isolating PostgreSQL workloads in Kubernetes using taints, labels, and anti-affinity rules with Kind and CloudNativePG."
tags: ["Fault tolerance", "GitOps pipelines", "High availability", "Infrastructure as Code", "IaC", "Kubernetes control plane", "Kubernetes scheduling", "Kubernetes nodes", "Multi-node cluster", "Node labels", "Node taints", "Node selectors", "PostgreSQL clustering", "Pod anti-affinity", "Production environment simulation", "Scheduling", "Workload isolation", "cloudnativepg", "cluster", "cnpg", "ci/cd pipelines", "cloudnative databases", "database cluster", "data on kubernetes", "developer productivity", "deployment automation", "docker", "dok", "e2e testing", "kubernetes", "k8s", "kind", "kubectl", "operator", "postgresql", "postgres"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In modern Kubernetes environments, isolating PostgreSQL workloads is crucial
for ensuring stability, security, and performance. This article, building on
the previous [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}}),
explores advanced techniques for isolating PostgreSQL instances using
Kubernetes with Kind. By applying taints, labels, and anti-affinity rules, you
can ensure that PostgreSQL nodes are dedicated exclusively to database
workloads, preventing overlap with other services and enhancing fault
tolerance. Whether you're simulating a production environment or managing a
live deployment, these strategies will help you maintain a robust and isolated
PostgreSQL cluster in Kubernetes._

<!--more-->

---

In [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}}), I
demonstrated how to set up a local Kind cluster with dedicated PostgreSQL nodes
using Kubernetes node labels and CloudNativePG node selectors for scheduling.
Specifically, I proposed using the `node-role.kubernetes.io/postgres` label to
designate nodes exclusively for PostgreSQL workloads.

While node labels and selectors help direct PostgreSQL workloads to specific
nodes, they do not fully isolate these workloads, which can lead to overlap
with other services or instances.

In this article, I will cover:

- Ensuring that PostgreSQL nodes exclusively run PostgreSQL workloads.
- Preventing multiple PostgreSQL instances within the same cluster from being
  scheduled on the same node.

To achieve better isolation, I propose using the
`node-role.kubernetes.io/postgres` taint, ensuring that PostgreSQL nodes are
dedicated solely to PostgreSQL workloads.

## Before You Start

Please review [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}})
before diving into this recipe, as it provides essential foundational knowledge
and setup necessary for this guide.

## Tainting Our Multi-Node Cluster

We will build on the multi-node cluster set up in [CNPG Recipe #10]({{< relref
"../20240814-kind-multi-node/index.md" >}}).

Our focus here is on applying a taint to each PostgreSQL node, ensuring that
only pods with the necessary tolerations can be scheduled and run on them.
Specifically, I propose using the `node-role.kubernetes.io/postgres` taint, as
demonstrated in the following Kind configuration file:

```yaml
{{< include "yaml/multi-node-taints-template.yaml" >}}
```

You’ll also notice an additional node —I’ll explain its purpose later.

To set up your cluster, download the
[multi-node-taints-template.yaml](yaml/multi-node-taints-template.yaml)
file and run the following command:

```sh
kind create cluster --config multi-node-taints-template.yaml --name cnpg
```

The output will confirm that your `kind` cluster is successfully up and
running.

Next, assign the appropriate `node-role.kubernetes.io/*` labels to the nodes:

```sh
# Assigning role labels to nodes based on existing labels
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=
```

After applying these labels, confirm they are correctly set by running:

```sh
kubectl get nodes
```

This will display the nodes and their labels, ensuring they are properly
configured:

```console
NAME                 STATUS   ROLES           AGE     VERSION
cnpg-control-plane   Ready    control-plane   5m14s   v1.31.0
cnpg-worker          Ready    infra           5m1s    v1.31.0
cnpg-worker2         Ready    app             5m1s    v1.31.0
cnpg-worker3         Ready    postgres        5m      v1.31.0
cnpg-worker4         Ready    postgres        5m1s    v1.31.0
cnpg-worker5         Ready    postgres        5m1s    v1.31.0
cnpg-worker6         Ready    <none>          5m1s    v1.31.0
```

To inspect the taints applied to a specific node, use:

```sh
kubectl describe node cnpg-worker5 | grep '^Taints'
```

This will confirm that the `cnpg-worker5` node has the `postgres` taint
applied.

You may have also noticed the spare node `cnpg-worker6`, which we will use
later.

## Isolating CNPG Clusters on `postgres` Nodes

In this recipe, I will focus exclusively on the `postgres` nodes, deliberately
excluding the `infra` and `app` nodes.

As outlined earlier, our goal is to create a PostgreSQL cluster using
CloudNativePG and ensure the following:

- **PostgreSQL workloads run exclusively on PostgreSQL nodes:** This aligns
  with the primary objective of [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}}).
- **PostgreSQL nodes are dedicated solely to PostgreSQL workloads:** This is
  partially achieved using the `node-role.kubernetes.io/postgres:NoSchedule`
  taint, which prevents non-PostgreSQL workloads from being scheduled on these
  nodes. The use of tolerations on PostgreSQL `Cluster` resources will fully
  enforce this isolation.
- **Instances of the same PostgreSQL `Cluster` are distributed across different
  nodes:** This ensures high availability and fault tolerance by enforcing pod
  anti-affinity rules, which schedule each instance on a separate node.

All of this is encapsulated in CloudNativePG through the following
`.spec.affinity` configuration:

```yaml
# <snip>
affinity:
  nodeSelector:
    node-role.kubernetes.io/postgres: ""

  # Set the toleration for the taint
  tolerations:
  - key: node-role.kubernetes.io/postgres
    operator: Exists
    effect: NoSchedule

  # Ensure that instances are scheduled and run on different nodes
  enablePodAntiAffinity: true
  topologyKey: kubernetes.io/hostname
  podAntiAffinityType: required
```

## Let's Get Started

First, [install the CloudNativePG operator](https://cloudnative-pg.io/documentation/current/installation_upgrade/#installation-on-kubernetes).

In this example, I'll use the latest development build of CloudNativePG for
testing:

```sh
curl -sSfL \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
  kubectl apply --server-side -f -
```

Verify that the operator is running:

```sh
kubectl get pods -A -o wide
```

The output should show that the operator is running on a non-Postgres node,
confirming that the taints are working.

Next, create the PostgreSQL cluster using the following manifest:

```yaml
{{< include "yaml/cluster-example.yaml" >}}
```

Download the [cluster-example.yaml](yaml/cluster-example.yaml) file and deploy
it with:

```sh
kubectl apply -f cluster-example.yaml
```

Finally, confirm that PostgreSQL workloads are running on the Postgres nodes by
running:

```sh
kubectl get pods -o wide
```

This should show that the PostgreSQL workloads are correctly isolated on the
designated Postgres nodes, ensuring that the taints and tolerations are
functioning as intended:

```console
NAME                READY   STATUS    RESTARTS   AGE     IP           NODE           NOMINATED NODE   READINESS GATES
cluster-example-1   1/1     Running   0          3m12s   10.244.7.4   cnpg-worker3   <none>           <none>
cluster-example-2   1/1     Running   0          2m34s   10.244.1.4   cnpg-worker5   <none>           <none>
cluster-example-3   1/1     Running   0          113s    10.244.4.4   cnpg-worker4   <none>           <none>
```

To ensure that no instances of the same PostgreSQL `Cluster` can be scheduled
on the same Postgres node, let's scale up the cluster to 4 instances:

```sh
kubectl scale cluster --replicas 4 cluster-example
```

If you observe the output of `kubectl get pods -w`, you’ll see that the fourth
instance remains in a pending state. Investigating further with:

```sh
kubectl describe pod cluster-example-4
```

will show that CloudNativePG enforces node selectors, pod anti-affinity rules,
and taints/tolerations, preventing any new scheduling due to the lack of
available Postgres nodes without an existing instance.

This is the expected behavior and confirms that our setup is working as
intended.

## What's Next?

In real-world scenarios, you would typically choose one of two exit strategies:

1. Adding a node for PostgreSQL
2. Scaling back to three instances (*rollback*)

### Adding a New Node for PostgreSQL

To simulate adding a new node for PostgreSQL, we'll use the spare node we
previously created in the cluster.

First, apply the PostgreSQL taint to the node:

```sh
kubectl taint node cnpg-worker6 node-role.kubernetes.io/postgres=:NoSchedule
```

You can verify the taint was applied correctly by running:

```sh
kubectl describe node cnpg-worker6 | grep '^Taints'
```

The expected output should confirm the taint:

```console
Taints:             node-role.kubernetes.io/postgres:NoSchedule
```

Next, assign the PostgreSQL node label to `cnpg-worker6`:

```sh
kubectl label node cnpg-worker6 node-role.kubernetes.io/postgres=
```

This final step will unblock the pending `cluster-example-4-join` job and
successfully create the third replica of `cluster-example`.

### Scaling Back to Three Instances

If the `cluster-example-4-join` job is pending, another option is to roll back
to the original two-replica PostgreSQL cluster.

To scale back, run:

```sh
kubectl scale cluster --replicas 3 cluster-example
```

Next, manually delete the pending job and its associated PVC:

```sh
kubectl delete job cluster-example-4-join
kubectl delete pvc cluster-example-4
```

This will restore the cluster to a healthy state.

## Conclusion

In this article, we demonstrated how to effectively isolate PostgreSQL
workloads within a Kubernetes environment using Kind.

By applying taints, labels, and anti-affinity rules, we directed PostgreSQL
workloads to specific nodes while isolating them from non-database workloads.
This approach strengthens the security and stability of your database clusters
while offering enhanced control over resource allocation.

Additionally, by employing Infrastructure as Code principles, we achieved a
clearer separation of responsibilities between database administrators (who
manage the `Cluster` resource, node selectors, tolerations, and pod
anti-affinity) and infrastructure administrators (who handle nodes, labels, and
taints).
This separation [streamlines management and fosters collaboration]({{< relref "../20240812-tshaped/index.md" >}}).

I also plan to [propose making the `node-role.kubernetes.io/postgres` labels and taints](https://github.com/cloudnative-pg/cloudnative-pg/issues/5305)
an official recommendation within the CloudNativePG project, promoting
the wider adoption of these best practices across the community.

In keeping with Cloud Native principles, the methods we explored in Kind are
fully portable across any Kubernetes-based platform—whether private, public,
hybrid, multi-cloud, or managed. This ensures that these strategies can be
consistently applied, regardless of the underlying infrastructure.

These techniques are crucial for those looking to simulate production
environments or manage PostgreSQL clusters with greater precision. As your
deployments grow in complexity, these strategies will be essential for
maintaining the performance, integrity, and reliability of your Kubernetes
workloads.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Varaha (Vishnu as boar) riding an Elephant“](https://picryl.com/media/varaha-vishnu-as-boar-riding-an-elephant-009d0f)._

