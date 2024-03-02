---
title: "CloudNativePG Recipe 1 - Setting up your local playground in minutes"
date: 2024-03-03
description: "How to setup your local playground in kind, install CloudNativePG and deploy your first PostgreSQL cluster"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "ci/cd pipelines", "e2e testing", "developer productivity", "deployment automation", "cloudnative databases"]
cover: cover.png
thumb: thumb.png
draft: false
---

_Dive into the world of running PostgreSQL in Kubernetes with
[CloudNativePG](https://cloudnative-pg.io/) in this inaugural guide. Follow
along as we walk you through the process of setting up a disposable local
cluster using [kind](https://kind.sigs.k8s.io/). Gain insights into creating
PostgreSQL clusters, installing CloudNativePG, and leveraging the `cnpg` plugin
for `kubectl`. Wrap up your journey by tidying up your local cluster. Whether
you're a developer or a DBA, this foundational guide provides a launchpad for
your future CloudNativePG explorations with a fully open source stack._

<!--more-->

---

Ciao! Welcome to my inaugural recipe on running Postgres in Kubernetes with
CloudNativePG: setting up your local playground.

The **objective** here is to effortlessly guide you through the process of
establishing a disposable local Kubernetes cluster on your laptop using
[kind](https://kind.sigs.k8s.io/). While other solutions like Minikube or k3d
exist, kind stands out as my preferred choice. It's lightweight, supports
multiple-node Kubernetes clusters, and is versatile enough to be employed in
any environment, including CI/CD pipelines. kind is compatible with Linux,
macOS, and Windows, and it holds the distinction of being a CNCF certified
conformant installer of Kubernetes.

To get started, install kind on your laptop by following the
["Quickstart"](https://kind.sigs.k8s.io/docs/user/quick-start).
Since you'll be interacting with a Kubernetes cluster, it's crucial to have
[kubectl](https://kubernetes.io/docs/tasks/tools/) installed as well.
Now, let's dive right in!

## Create Your First Kubernetes Cluster

Start by confirming your kind installation using the following command:

```sh
kind version
```

On my laptop, as of the time of writing, the output is
`kind v0.22.0 go1.21.7 darwin/amd64`.

Now, proceed to establish your initial local Kubernetes cluster for
CloudNativePG with:

```sh
kind create cluster --name cnpg
```

Upon execution, you'll observe the following output:

```console
Creating cluster "cnpg" ...
 ✓ Ensuring node image (kindest/node:v1.29.2) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-cnpg"
You can now use your cluster with:

kubectl cluster-info --context kind-cnpg

Unsure about the next steps? 😅 Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```

There you have it – the `cnpg` Kubernetes cluster is now operational within
containers. To confirm, run:

```sh
kind get clusters
```

Congratulations on successfully creating your local Kubernetes environment!

### There's more ...

By default, kind generates a Kubernetes cluster with a single node. If you're
eager to experiment with multiple nodes, simulating the distribution of
PostgreSQL instances, explore the
["Nodes"](https://kind.sigs.k8s.io/docs/user/configuration/#nodes) section in
the kind documentation for detailed insights and configuration options.

## Install CloudNativePG

Now that our local Kubernetes playground is set up, let's explore the
installation of CloudNativePG.

To deploy the latest stable version, refer to the
[CloudNativePG documentation for instructions on installing the operator via Kubernetes manifests](https://cloudnative-pg.io/documentation/current/installation_upgrade/#directly-using-the-operator-manifest).

For instance, to install version 1.22.1, the latest available at the time of
writing, use the following command:

```sh
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml
```

This command creates a `Deployment` resource named `cnpg-controller-manager`
within the `cnpg-system` namespace of your Kubernetes cluster. The deployment
should complete in a few seconds, and you can monitor its progress with:

```sh
kubectl get deployment -n cnpg-system cnpg-controller-manager
```

### There's more ...

For those who are as adventurous as our maintainers, you can install the latest
development snapshot from the CloudNativePG trunk (yes, we embrace
[trunk-based development](https://dora.dev/devops-capabilities/technical/trunk-based-development/)
at CloudNativePG) using the following command:

```sh
curl -sSfL \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml \
  | kubectl apply --server-side -f -
```

Feel free to explore different versions or dive into the latest developments!

## Create Your First PostgreSQL Cluster

With CloudNativePG successfully installed in your local cluster, creating your
initial 3-instance PostgreSQL cluster is a breeze.

Let's utilize the basic
[cluster-example](https://cloudnative-pg.io/documentation/current/samples/cluster-example.yaml)
file provided by CloudNativePG for evaluation purposes. The YAML content is
concise, under 10 lines, and adheres to the *convention over configuration*
paradigm embraced by CloudNativePG. This default configuration should
seamlessly work for most use cases, and all available options are detailed in
the [API reference](https://cloudnative-pg.io/documentation/current/cloudnative-pg.v1/),
giving you the flexibility to override any of them.

Here's a snippet of the YAML file:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: cluster-example
spec:
  instances: 3

  storage:
    size: 1Gi
```

Deploying this cluster, like any other Kubernetes resource, is a one-liner
using the `kubectl apply` command:

```sh
kubectl apply -f \
  https://cloudnative-pg.io/documentation/current/samples/cluster-example.yaml
```

Monitor the progress with `kubectl get pods -w`.

Once CloudNativePG creates the first instance (`cluster-example-1`), it
promptly clones the first replica (`cluster-example-2`) and immediately follows
up with the second replica (`cluster-example-3`). This process typically takes
around a minute.

Verify the `Cluster` resource with:

```sh
kubectl get cluster cluster-example
```

On my laptop, the output is:

```console
NAME              AGE     INSTANCES   READY   STATUS                     PRIMARY
cluster-example   4m18s   3           3       Cluster in healthy state   cluster-example-1
```

Congratulations! You now have your first PostgreSQL cluster up and running with
CloudNativePG.

## The `cnpg` plugin for `kubectl`

CloudNativePG eschews the need for a standalone command line interface (CLI)
and seamlessly integrates with `kubectl` through its dedicated plugin known as
`cnpg`. This plugin facilitates a direct interface with CloudNativePG
deployments using the concise `kubectl cnpg` command.

Installation of the plugin offers flexibility through various methods,
including package installations outlined in the
[CloudNativePG documentation](https://cloudnative-pg.io/documentation/current/kubectl-plugin/).

We strongly endorse the `cnpg` plugin, with one notable advantage being the
inclusion of the `cnpg status` command.

Once the plugin is installed, execute the following command to experience its
capabilities firsthand:

```sh
kubectl cnpg status cluster-example
```

This command typically yields output similar to:

```console
Cluster Summary
Name:                cluster-example
Namespace:           default
System ID:           7342047578820919323
PostgreSQL Image:    ghcr.io/cloudnative-pg/postgresql:16.1
Primary instance:    cluster-example-1
Primary start time:  2024-03-03 08:14:28 +0000 UTC (uptime 14m32s)
Status:              Cluster in healthy state
Instances:           3
Ready instances:     3
Current Write LSN:   0/8000000 (Timeline: 1 - WAL File: 000000010000000000000007)

Certificates Status
Certificate Name             Expiration Date                Days Left Until Expiration
----------------             ---------------                --------------------------
cluster-example-ca           2024-06-01 08:09:01 +0000 UTC  89.99
cluster-example-replication  2024-06-01 08:09:01 +0000 UTC  89.99
cluster-example-server       2024-06-01 08:09:01 +0000 UTC  89.99

Continuous Backup status
Not configured

Physical backups
No running physical backups found

Streaming Replication status
Replication Slots Enabled
Name               Sent LSN   Write LSN  Flush LSN  Replay LSN  Write Lag  Flush Lag  Replay Lag  State      Sync State  Sync Priority  Replication Slot
----               --------   ---------  ---------  ----------  ---------  ---------  ----------  -----      ----------  -------------  ----------------
cluster-example-2  0/8000000  0/8000000  0/8000000  0/8000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active
cluster-example-3  0/8000000  0/8000000  0/8000000  0/8000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active

Unmanaged Replication Slot Status
No unmanaged replication slots found

Managed roles status
No roles managed

Tablespaces status
No managed tablespaces

Instances status
Name               Database Size  Current LSN  Replication role  Status  QoS         Manager Version  Node
----               -------------  -----------  ----------------  ------  ---         ---------------  ----
cluster-example-1  29 MB          0/8000000    Primary           OK      BestEffort  1.22.1           cnpg-control-plane
cluster-example-2  29 MB          0/8000000    Standby (async)   OK      BestEffort  1.22.1           cnpg-control-plane
cluster-example-3  29 MB          0/8000000    Standby (async)   OK      BestEffort  1.22.1           cnpg-control-plane
```

This tool becomes indispensable as it provides essential insights into your
CloudNativePG deployment. Moreover, a myriad of other commands is at your
disposal. For a comprehensive list, refer to the documentation or simply type
`kubectl cnpg help`.

## Cleanup

As we conclude, let's maintain orderliness by responsibly removing the
Kubernetes cluster recently created from your local container engine platform.
This step adheres to our standard practice, mirrored in our CI/CD pipelines for
[end-to-end (E2E) testing in CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg/tree/main/contribute/e2e_testing_environment).

Execute the following command to gracefully delete the `cnpg` cluster in kind:

```sh
kind delete cluster --name cnpg
```

Wishing you smooth sailing!

## Conclusions

I trust the provided information has armed you with the knowledge to venture
into running PostgreSQL in Kubernetes with CloudNativePG. This recipe stands as
a valuable reference in the blog, serving as a compass for future explorations
into specific CloudNativePG topics.

Stay tuned for upcoming recipes! Don't forget to subscribe to my
[LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[X](https://twitter.com/_GBartolini_) channels for the latest updates.

If you found this article insightful, consider sharing it with your network on
social media using the links provided below. Your support is greatly
appreciated!
