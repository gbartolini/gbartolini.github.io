---
title: "CloudNativePG Recipe 11 - Isolating PostgreSQL workloads in Kubernetes with Kind"
date: 2024-08-14T12:37:51+02:00
description: "This article guides readers through deploying PostgreSQL on Kubernetes using kind to create multi-node clusters on a local machine, simulating production environments with node taints and workload isolation techniques."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "ci/cd pipelines", "e2e testing", "developer productivity", "deployment automation", "cloudnative databases", "docker", "Multi-node cluster", "Node labels", "Node taints", "Workload isolation", "Infrastructure as Code", "IaC", "Kubernetes control plane", "GitOps pipelines", "kubectl", "Node selectors", "Kubernetes scheduling", "PostgreSQL clustering"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_
_

<!--more-->

---

In [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}}), I
demonstrated how to set up a local Kind cluster with dedicated PostgreSQL nodes
using Kubernetes node labels and CloudNativePG node selectors for scheduling.
Specifically, I proposed using the `node-role.kubernetes.io/postgres` label to
designate nodes exclusively for PostgreSQL.

While node labels and node selectors help direct PostgreSQL workloads to
specific nodes, they do not fully isolate these workloads, allowing for
potential overlap with other services or instances. 

In this article, I will address:

- How to ensure that PostgreSQL nodes exclusively run PostgreSQL workloads
- How to prevent PostgreSQL instances from being scheduled on the same node
  within the same cluster

I am proposing the use of the `node-role.kubernetes.io/postgres` taint to
achieve better isolation for PostgreSQL nodes, ensuring that they are dedicated
solely to PostgreSQL workloads.

## Before You Start

Please ensure you have reviewed [CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}})
before diving into this recipe, as it provides essential foundational knowledge
and setup necessary for this guide.

## Tainting Our Multi-Node Cluster

In this article, we will build on the multi-node cluster set up in
[CNPG Recipe #10]({{< relref "../20240814-kind-multi-node/index.md" >}}).

Our focus is on applying a taint to each PostgreSQL node, ensuring that only
pods with the necessary tolerations can be scheduled and run on them.
Specifically, I propose using the `node-role.kubernetes.io/postgres` taint, as
demonstrated in the following Kind configuration file:

```yaml
{{< include "yaml/multi-node-taints-template.yaml" >}}
```

You'll also notice an additional node labeled `spare.node.kubernetes.io`—I'll
explain the purpose of this node later.

To set up your cluster, download the
[multi-node-taints-template.yaml](yaml/multi-node-taints-template.yaml)
file and run the following command:

```sh
kind create cluster --config multi-node-taints-template.yaml --name cnpg
```

Returning:

```console
Creating cluster "cnpg" ...
 ✓ Ensuring node image (kindest/node:v1.31.0) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-cnpg"
You can now use your cluster with:

kubectl cluster-info --context kind-cnpg

Thanks for using kind! 😊
```

Our `kind` cluster is now successfully up and running. As described in CNPG
Recipe #10, we will now assign the appropriate `node-role.kubernetes.io/*`
labels to the nodes for better role management:

```sh
# Assigning role labels to nodes based on existing labels
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=
```

After applying these labels, you can confirm that the labels have been
correctly set by running the following command:

```sh
kubectl get nodes
```

This will display the nodes along with their labels, ensuring that the role
labels are properly configured:

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

To inspect the taints applied to a specific node, you can use the `kubectl
describe node` command and focus on the `Taints` field.
For instance, to verify the taints on the `cnpg-worker5` node, you can run the
following command:

```sh
kubectl describe node cnpg-worker5 | grep '^Taints'
```

This will return the taints applied to the node, such as:

```
Taints:             node-role.kubernetes.io/postgres:NoSchedule
```

This output confirms that the `cnpg-worker5` node has a taint that restricts
scheduling of non-postgres workloads.

You may have also noticed the spare node `cnpg-worker6`.

## Isolating CNPG Clusters on `postgres` Nodes

In this recipe, we will concentrate exclusively on the `postgres` nodes,
deliberately excluding the `infra` and `app` nodes from our focus.

As outlined at the beginning of this article, our goal is to declaratively
create a PostgreSQL cluster using CloudNativePG and ensure the following:

- **PostgreSQL workloads run exclusively on PostgreSQL nodes:** This aligns
  with the primary objective of CNPG Recipe #9.
- **PostgreSQL nodes are dedicated solely to PostgreSQL workloads:** This has
  been partially implemented using the
  `node-role.kubernetes.io/postgres:NoSchedule` taint, which prevents
  non-PostgreSQL workloads from being scheduled on these nodes. The use of
  tolerations on PostgreSQL `Cluster` resources will fully enforce this
  isolation.
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

First, let's [install the CloudNativePG operator](https://cloudnative-pg.io/documentation/current/installation_upgrade/#installation-on-kubernetes).
In this example, we'll use the latest development build of CloudNativePG:

```sh
curl -sSfL \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
  kubectl apply --server-side -f -
```

Next, verify that the operator is running:

```sh
kubectl get pods -A -o wide
```

You'll see that the operator is running on a non-Postgres node (e.g.,
`cnpg-worker`), confirming that taints are working:

```console
NAMESPACE    NAME                                     READY   STATUS    RESTARTS   AGE     IP           NODE                 NOMINATED NODE   READINESS GATES
cnpg-system  cnpg-controller-manager-df7cb8999-t28r5  1/1     Running   0          2m8s    10.244.6.2   cnpg-worker2         <none>           <none>
k
# <snip>
```

Now, let's proceed by creating the PostgreSQL cluster using the following
manifest:

```yaml
{{< include "yaml/cluster-example.yaml" >}}
```

Download the [cluster-example.yaml](yaml/cluster-example.yaml) file and deploy
it with:

```sh
kubectl apply -f cluster-example.yaml
```

Finally, confirm that PostgreSQL workloads are running on the Postgres nodes
(e.g., `cnpg-worker3`, `cnpg-worker4`, `cnpg-worker5`) by using:

```sh
kubectl get pods -o wide
```

You should see an output similar to this:

```console
NAME                READY   STATUS    RESTARTS   AGE     IP           NODE           NOMINATED NODE   READINESS GATES
cluster-example-1   1/1     Running   0          3m12s   10.244.7.4   cnpg-worker3   <none>           <none>
cluster-example-2   1/1     Running   0          2m34s   10.244.1.4   cnpg-worker5   <none>           <none>
cluster-example-3   1/1     Running   0          113s    10.244.4.4   cnpg-worker4   <none>           <none>
```

This confirms that the PostgreSQL workloads are correctly isolated on the
designated Postgres nodes, ensuring that the taints and tolerations are
functioning as intended.

The final step in our validation is to ensure that no instances of the same
PostgreSQL `Cluster` can be scheduled on the same Postgres node. To test this,
let's scale up the cluster to 4 instances:

```sh
kubectl scale cluster --replicas 4 cluster-example
```

If you run `kubectl get pods -w`, you'll notice that something is amiss:

```console
NAME                           READY   STATUS    RESTARTS   AGE
NAME                           READY   STATUS    RESTARTS   AGE
cluster-example-1              1/1     Running   0          3m58s
cluster-example-2              1/1     Running   0          3m20s
cluster-example-3              1/1     Running   0          2m39s
cluster-example-4-join-thr9s   0/1     Pending   0          24s
```

The fourth instance remains in a pending state.

To investigate further, use the following command:

```sh
kubectl describe pod cluster-example-4
```

As you'll see, CloudNativePG enforces the node selector, pod anti-affinity, and
taints/tolerations to prevent any new scheduling, because there are no
available Postgres nodes without an existing instance of the cluster:

```console
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  46s   default-scheduler  0/7 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 3 node(s) didn't match Pod's node affinity/selector, 3 node(s) didn't match pod anti-affinity rules. preemption: 0/7 nodes are available: 3 No preemption victims found for incoming pod, 4 Preemption is not helpful for scheduling.
```

This is exactly the behavior we were aiming for!

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

TODO

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephant Riding“](https://www.freeimageslive.co.uk/taxonomy/term/6)._

