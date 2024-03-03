---
title: "CloudNativePG Recipe 10 - Simulating Production PostgreSQL on Kubernetes with Kind"
date: 2024-08-14T12:37:51+02:00
description: "This article guides readers through deploying PostgreSQL on Kubernetes using kind to create multi-node clusters on a local machine, simulating production environments with node labeling and workload isolation techniques."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "ci/cd pipelines", "e2e testing", "developer productivity", "deployment automation", "cloudnative databases", "docker", "Multi-node cluster", "Node labels", "Node taints", "Workload isolation", "Infrastructure as Code", "IaC", "Kubernetes control plane", "GitOps pipelines", "kubectl", "Node selectors", "Kubernetes scheduling", "PostgreSQL clustering"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_This article provides a step-by-step guide to deploying PostgreSQL in
Kubernetes using the `kind` tool (Kubernetes IN Docker) on a local machine,
simulating a production-like environment. It explains how to create multi-node
clusters and use node labels, specifically proposing the
`node-role.kubernetes.io/postgres` label to designate PostgreSQL nodes. The
article also demonstrates how to schedule PostgreSQL instances on these
designated nodes, emphasizing the importance of workload isolation in
Kubernetes environments. Thanks to Kubernetes' portability, these
recommendations apply to any cloud deployment—whether private, public,
self-managed, or fully managed._

<!--more-->

---

One standout tool in the Kubernetes ecosystem is
[kind](https://kind.sigs.k8s.io/), short for Kubernetes IN Docker. This tool
enables you to run a full Kubernetes cluster using nodes that operate as Docker
containers. It offers a portable, consistent environment for testing your
applications, ensuring smooth transitions from development to production, and
seamlessly integrating them into your GitOps pipelines.

In ["CloudNativePG Recipe 1 - Setting up your local playground in minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}}),
I introduced the basics of getting started.

In this article, I'll take it a step further by showing how to use `kind` to
create local Kubernetes clusters with multiple nodes, each dedicated to
specific tasks like the control plane, applications, and PostgreSQL workloads.

Additionally, I’ll show how to isolate PostgreSQL workloads by assigning
specific nodes using node labels, ensuring clear separation between databases
and applications at the "physical" level. In a future article, I'll dive deeper
into advanced techniques like node taints and anti-affinity for even greater
control.

In this article, I am proposing the use of the
`node-role.kubernetes.io/postgres` label to specifically designate nodes for
PostgreSQL workloads.

## Before You Start

Before you proceed, ensure that you have the following installed on your
laptop:

- [kind](https://kind.sigs.k8s.io/docs/user/quick-start)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

If you're new to CloudNativePG, I recommend spending 5-10 minutes reviewing
[“CNPG Recipe 1”]({{< relref "../20240303-recipe-local-setup/index.md" >}})
mentioned earlier.

## Our First Multi-Node Cluster

By now, you should be comfortable creating a basic Kubernetes cluster with
`kind`. While the default setup creates a single-node cluster that works well
for many scenarios, it falls short when you want to explore advanced
CloudNativePG and Kubernetes features like node selectors, taints &
tolerations, affinity, and anti-affinity. To fully leverage these capabilities,
you'll need to simulate a multi-node cluster.

Fortunately, `kind` allows you to customise the default installation using a
configuration file.  We’ll leverage this feature to create a Kubernetes cluster
with multiple nodes and apply basic labels to them, as follows:

- 1 node dedicated to hosting the Kubernetes control plane
- 1 worker node with a label `infra.node.kubernetes.io` for potential
  infrastructure workloads (e.g., Prometheus, Grafana)
- 1 worker node with a label `app.node.kubernetes.io` for potential application
  hosting (e.g., pgbench in our case)
- 3 worker nodes with a label `postgres.node.kubernetes.io` for deploying
  PostgreSQL instances

---

_As you may have noticed, I’ve adopted the following naming convention for
labels: `ROLE.node.kubernetes.io`, where `ROLE` can be `infra`, `app`, or
`postgres`. While other conventions could be used, I’ve chosen this approach
for specific reasons, which I’ll explain in the next section._

---

All of the above can be transformed into infrastructure as code with this
simple YAML file to configure a `kind` `Cluster` resource:

```yaml
{{< include "yaml/multi-node-template.yaml" >}}
```

Download the content of the [multi-node-template.yaml](yaml/multi-node-template.yaml) file and then run:

```sh
kind create cluster --config multi-node-template.yaml --name cnpg
```

Returning:

```console
Creating cluster "cnpg" ...
 ✓ Ensuring node image (kindest/node:v1.30.0) 🖼
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

Our `kind` cluster is now up and running. Let’s start by checking the available
nodes:

```sh
kubectl get nodes
```

This command will return:

```console
NAME                 STATUS   ROLES           AGE     VERSION
cnpg-control-plane   Ready    control-plane   5m4s    v1.30.0
cnpg-worker          Ready    <none>          4m44s   v1.30.0
cnpg-worker2         Ready    <none>          4m44s   v1.30.0
cnpg-worker3         Ready    <none>          4m45s   v1.30.0
cnpg-worker4         Ready    <none>          4m44s   v1.30.0
cnpg-worker5         Ready    <none>          4m45s   v1.30.0
```

As you can see, only the `cnpg-control-plane` node has a `control-plane` role.
The other nodes show `<none>` under the `ROLES` column. Why is that?

## Understanding Well-Known Node Labels in Kubernetes

The reason lies in how Kubernetes labels nodes.
Kubernetes uses a specific label,
[`node-role.kubernetes.io/control-plane`](https://kubernetes.io/docs/reference/labels-annotations-taints/#node-role-kubernetes-io-control-plane),
to identify nodes running the control plane. The `kubectl get nodes` command
extracts the `role` information from the string following
`node-role.kubernetes.io/`, which in this case is `control-plane`.

To display roles for the worker nodes, such as `infra`, `app`, and `postgres`,
we need to manually assign the appropriate labels:

- `node-role.kubernetes.io/infra`
- `node-role.kubernetes.io/app`
- `node-role.kubernetes.io/postgres`

However, by default, the `kubelet` restricts the assignment of labels within
the `kubernetes.io` namespace unless they have either the `kubelet` or `node`
prefix, as a security measure. This behaviour is described in the
[Kubelet command-line reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
and is also discussed in [this `kubeadm` issue](https://github.com/kubernetes/kubeadm/issues/2509).

A common workaround is to use the `kubectl label node` command after the nodes
are created. You can apply the desired labels like this:

```sh
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=
```

Now, if you rerun the `kubectl get nodes` command, you should see the updated roles:

```console
NAME                 STATUS   ROLES           AGE   VERSION
cnpg-control-plane   Ready    control-plane   19m   v1.30.0
cnpg-worker          Ready    infra           19m   v1.30.0
cnpg-worker2         Ready    app             19m   v1.30.0
cnpg-worker3         Ready    postgres        19m   v1.30.0
cnpg-worker4         Ready    postgres        19m   v1.30.0
cnpg-worker5         Ready    postgres        19m   v1.30.0
```

This output makes it clear that we have six nodes, each ideally dedicated to
running the control plane, application workloads, infrastructure services, and
Postgres databases.

### There's More...

By now, it should be clear why I chose the `ROLE.node.kubernetes.io`
convention in the first place.
This approach allows you to easily apply the desired labels using selectors
with `kubectl label node`.
Alternatively, you can use the same command to label individual nodes directly,
which is a common practice for Kubernetes administrators when adding new nodes
to a cluster. For example:

```sh
kubectl label node cnpg-worker5 node-role.kubernetes.io/postgres=
```

## Scheduling CNPG Clusters on `postgres` Nodes

Let's set aside the `infra` and `app` nodes for now and focus solely on the
`postgres` nodes.

Our objective is to declaratively create a PostgreSQL cluster using
CloudNativePG and ensure it runs on the designated `postgres` nodes.

This is a straightforward task in Kubernetes, thanks to [node selectors](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/).
CloudNativePG leverages this capability through the
`.spec.affinity.nodeSelector` field, as described in the
[“Scheduling” documentation](https://cloudnative-pg.io/documentation/current/scheduling/#node-selection-through-nodeselector),
illustrated by the following example:

```yaml
# <snip>
  affinity:
    nodeSelector:
      node-role.kubernetes.io/postgres: ""
```

## Let's Get Started

First, ensure [the operator is installed](https://cloudnative-pg.io/documentation/current/installation_upgrade/#installation-on-kubernetes).
Feel free to install the version of your choice. For production environments,
it’s recommended to use the latest stable minor release.

As a maintainer, I’m using the latest development build of CloudNativePG on my
`kind` cluster:

```sh
curl -sSfL \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
  kubectl apply --server-side -f -
```

Wait for the operator to be fully installed and running. You can verify its
status with:

```sh
kubectl get pods -A -o wide
```

The output will show that workloads are distributed across all nodes, including
the PostgreSQL nodes:

```console
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE   IP           NODE                 NOMINATED NODE   READINESS GATES
cnpg-system          cnpg-controller-manager-7bd984695d-ptzs8     1/1     Running   0          47s   10.244.2.2   cnpg-worker5         <none>           <none>
kube-system          coredns-7db6d8ff4d-hxw9q                     1/1     Running   0          40m   10.244.0.4   cnpg-control-plane   <none>           <none>
kube-system          coredns-7db6d8ff4d-rgd84                     1/1     Running   0          40m   10.244.0.2   cnpg-control-plane   <none>           <none>
# <snip>
```

This is expected since we didn’t apply any restrictions to prevent non-Postgres
workloads, including the operator, from running on the Postgres nodes. I’ll
cover workload isolation and node reservation in a future article.

With the operator installed, you can now create the PostgreSQL cluster:

```yaml
{{< include "yaml/cluster-example.yaml" >}}
```

Download the content of the [cluster-example.yaml](yaml/cluster-example.yaml)
file and apply it:

```sh
kubectl apply -f cluster-example.yaml
```

Once the cluster creation is complete, running `kubectl get pods -o wide`
should yield the following output, confirming that PostgreSQL workloads are
indeed running on the nodes labeled with `node-role.kubernetes.io/postgres`
(workers 3, 4 and 5):

```console
NAME                READY   STATUS    RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES
cluster-example-1   1/1     Running   0          96s   10.244.4.4   cnpg-worker4   <none>           <none>
cluster-example-2   1/1     Running   0          54s   10.244.1.4   cnpg-worker3   <none>           <none>
cluster-example-3   1/1     Running   0          13s   10.244.2.5   cnpg-worker5   <none>           <none>
```

Success! Your PostgreSQL cluster is now correctly scheduled on the `postgres`
nodes.

## Conclusion

Kind is an exceptional tool that brings the power of Kubernetes directly to
your laptop, enabling us to simulate real-world scenarios. This allows us to
effectively plan and design PostgreSQL architectures in Kubernetes using
Infrastructure as Code (IaC). The combination of Kind, Kubernetes,
CloudNativePG, and PostgreSQL—all open-source—empowers us to experiment,
practice, and test our infrastructure and applications consistently from
development to production. This process can even be automated through GitOps
pipelines. To emphasise key concepts introduced by Gene Kim and Steven J.
Spear, this approach embodies [slowification, simplification, and amplification](https://itrevolution.com/articles/moving-from-the-danger-zone-to-the-winning-zone/)
— topics I partially covered in my [previous article]({{< relref "../20240812-tshaped/index.md" >}}).

Thanks to Kubernetes' portability, these recommendations apply to any cloud
deployment—whether private, public, self-managed, or fully managed.

Node labels are a critical technique for controlling the "physical" scheduling
of PostgreSQL workloads in Kubernetes through declarative configuration. They
provide Postgres DBAs and experts with a way to manage the "cattle vs. pets"
paradigm, ensuring that even the elephants — PostgreSQL — have a place in the game.
By using node labels, we can precisely determine which workloads run on
specific nodes. You can also apply additional labels to gain finer control,
such as dedicating specific machines to a single PostgreSQL cluster, or using
bare metal nodes with local disks.

However, as we've seen, node labels alone are not sufficient to fully isolate
PostgreSQL workloads. In the example above, the operator
(`cnpg-system.cnpg-controller-manager-*`) was running on `cnpg-worker5`, which
also hosted PostgreSQL primaries. If an issue arises on that node, it could
delay failover processes. Therefore, it's crucial to ensure that the operator
is installed on nodes where PostgreSQL is not running.

Don't worry — I’ll cover this scenario in the next article.

P.S.: Special thanks to my colleagues and fellow maintainers Leonardo Cecchi,
Francesco Canovai, and Jonathan Gonzalez for their invaluable help.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Elephant Riding“](https://www.freeimageslive.co.uk/taxonomy/term/6)._

