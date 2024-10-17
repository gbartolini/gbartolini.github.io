---
title: "CNPG Recipe 12 - Exposing Postgres outside Kubernetes with Service Templates"
date: 2024-08-26T09:38:30+02:00
description: "How to use CloudNativePG 1.24's service templates to create `LoadBalancer` services for exposing PostgreSQL outside Kubernetes clusters."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "load balancer", "exposing", "cloud-provider-kind" , "Service templates" , "LoadBalancer services" , "DBaaS deployment" , "Kubernetes database" , "Managed services" , "External database access" , "Custom services Kubernetes" ]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In this article, I'll introduce you to the new service template feature in
CloudNativePG 1.24, which greatly simplifies the creation of services such as
`LoadBalancer` to expose PostgreSQL outside of your Kubernetes cluster -
particularly useful for streamlining Database-as-a-Service (DBaaS) deployments.
 I’ll walk you through setting up this feature on your laptop using `kind` and
`cloud-provider-kind`, ensuring you can easily test and implement these
capabilities in your own environment._

<!--more-->

_NOTE: this article has been updated on October 17th, 2024 with the most recent
version of `cloudnative-pg`._

---

[CloudNativePG 1.24](https://cloudnative-pg.io/releases/cloudnative-pg-1-24.0-released/)
introduces managed services and service templates, making it easier than ever
to create additional services—like `LoadBalancer`—to expose PostgreSQL outside
your Kubernetes cluster. This new feature is a game-changer for simplifying
DBaaS deployments.

To help you get started, I'll show you how to test this feature on your laptop
using `kind` and `cloud-provider-kind`. Let’s dive in!

## The Context

PostgreSQL databases deployed through CloudNativePG are becoming increasingly
common in DBaaS environments. Major players like IBM Cloud Pak, GKE, AKS,
Tembo, and my company, EDB, all rely on CloudNativePG to manage their database
services (see [ADOPTERS.md](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md)).

In these setups, it's typical for the application and database to
reside in different Kubernetes clusters, necessitating external access to the
database services. This is especially important for exposing the primary
service for read-write operations or a replica for read-only operations.

Traditionally, exposing a PostgreSQL cluster outside of the Kubernetes
environment required manually creating a `LoadBalancer` service or configuring
an Ingress. While effective, this process added complexity and overhead to
DBaaS deployments.

With the release of CloudNativePG 1.24, this task has become significantly
easier. You can now define custom services for any PostgreSQL `Cluster`
resource using service templates, making it straightforward to expose your
databases to external clients - even for evaluation purposes.

## Before You Start

Before diving in, ensure that you can locally deploy a `kind` cluster, as
explained in [CNPG Recipe #1]({{< relref "../20240303-recipe-local-setup/index.md" >}}).

However, `kind` alone is not sufficient to simulate the external load balancer
functionality typical of a cloud provider. For this, you'll need an additional
component called [Cloud Provider KIND](https://github.com/kubernetes-sigs/cloud-provider-kind).

## Setting Up the Local Environment

We’ll start by creating a new cluster with `kind` to evaluate the
`LoadBalancer` service via Cloud Provider KIND, as detailed in the
[documentation](https://kind.sigs.k8s.io/docs/user/loadbalancer/).

First, [install the `cloud-provider-kind` executable on your system](https://github.com/kubernetes-sigs/cloud-provider-kind?tab=readme-ov-file#install).
The installation method depends on your operating system. On my MacBook, I
chose to install it using Go:

```sh
go install sigs.k8s.io/cloud-provider-kind@latest
```

Next, open a terminal and run `cloud-provider-kind` in the background (on
macOS, you may need to run it with `sudo`):

```sh
sudo cloud-provider-kind
```

In another terminal, you can now create a basic `kind` cluster with a single
node, as explained in Recipe #1:

```sh
kind create cluster --name cnpg
```

Once your cluster is up and running, [install the CloudNativePG operator](https://cloudnative-pg.io/documentation/current/installation_upgrade/).
There are multiple installation methods, but I prefer using manifests:

```sh
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.24.1.yaml
```

## Creating the PostgreSQL Cluster

Now, let’s create our PostgreSQL cluster and leverage the [managed services](https://cloudnative-pg.io/documentation/current/service_management/)
feature in CloudNativePG. Specifically, we’ll:

- Disable the creation of the read-only and read services, which are normally
  created by default.
- Create an external load balancer service to connect to the primary instance.

In true declarative fashion, the manifest below is self-explanatory:

```yaml
{{< include "yaml/cluster-example.yaml" >}}
```

As you may have noticed, the `disabledDefaultServices` option allows you to
disable the creation of the `-ro` and `-r` services, which are typically
created by default using the `ClusterIP` type.

The `additional` stanza lets you define custom services using the
`serviceTemplate` field, granting full access to the Kubernetes `Service` API.
This is particularly valuable in production environments within the cloud, as
the `metadata` section can be used to add annotations that control the load
balancer and that depend on the specific cloud provider.
In this example, I request the creation of a `LoadBalancer` service named
`cluster-example-rw-lb`, which is configured to point to the primary (`rw`).

Download the [cluster-example.yaml](yaml/cluster-example.yaml) file and deploy
it with the following command:

```sh
kubectl apply -f cluster-example.yaml
```

As usual, monitor the deployment progress using `kubectl get pods -w`. Once the
deployment is complete, check the services to see what has been created:

```sh
kubectl get service
```

You should see two services listed: a mandatory `ClusterIP` service for the
primary (`cluster-example-rw`), and a `LoadBalancer` service called
`cluster-example-rw-lb` with an external IP address, in this case,
`172.18.0.4`:

```console
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
cluster-example-rw-lb   LoadBalancer   10.96.58.150    172.18.0.4    5432:31096/TCP   3s
cluster-example-rw      ClusterIP      10.96.121.235   <none>        5432/TCP         3s
kubernetes              ClusterIP      10.96.0.1       <none>        443/TCP          20m
```

Run `kubectl describe service cluster-example-rw-lb` to get more information,
paying attention to the `Selector` part:

```console
Name:                     cluster-example-rw-lb
Namespace:                default
Labels:                   cnpg.io/cluster=cluster-example
                          cnpg.io/isManaged=true
Annotations:              cnpg.io/operatorVersion: 1.24.1
                          cnpg.io/updateStrategy: patch
Selector:                 cnpg.io/cluster=cluster-example,cnpg.io/instanceRole=primary
Type:                     LoadBalancer
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.58.150
IPs:                      10.96.58.150
LoadBalancer Ingress:     172.18.0.4 (Proxy)
Port:                     postgres  5432/TCP
TargetPort:               5432/TCP
NodePort:                 postgres  31096/TCP
Endpoints:                10.244.0.16:5432
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:
  Type    Reason                Age   From                Message
  ----    ------                ----  ----                -------
  Normal  EnsuringLoadBalancer  54m   service-controller  Ensuring load balancer
  Normal  EnsuredLoadBalancer   54m   service-controller  Ensured load balancer
```

## Verifying External Connectivity with `psql`

Next, let's confirm that we can connect to the PostgreSQL database from outside
the Kubernetes cluster. I'll be using `psql`, the widely-used command-line
interface for PostgreSQL, which is available on all major platforms. On my Mac,
I installed it via Homebrew:

```sh
brew install postgresql@16
brew link postgresql@16
```

Ensure the installation is successful by checking the version:

```console
psql --version
```

You should see something like this (16.4 is the latest at the time of writing):

```console
psql (PostgreSQL) 16.4 (Homebrew)
```

Now, let's verify the connection to the database:

```sh
psql -h 172.18.0.4 -U app app
```

If the connection is successful, you'll be prompted to enter a password:

```console
Password for user app:
```

As detailed in [CNPG Recipe #2](https://www.gabrielebartolini.it/articles/2024/03/cloudnativepg-recipe-2-inspecting-default-resources-in-a-cloudnativepg-cluster/),
you can retrieve the password using the following command:

```sh
kubectl get secret cluster-example-app \
  -o jsonpath="{.data.password}" | base64 -d
```

Copy the retrieved password, paste it into the `psql` prompt, and you should be
connected to the database, seeing output similar to this:

```console
psql (16.4 (Homebrew))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

app=>
```

Success! You've now connected to the `app` database running inside your
Kubernetes cluster from an external environment.

Although I’m using `psql` in this example, this approach should work with any
PostgreSQL client application, including GUIs like pgAdmin, offering
flexibility depending on your preferred tools.

## There's More...

If you plan to test `kind` with multiple nodes, you'll notice that the control
plane nodes are labeled with `node.kubernetes.io/exclude-from-external-load-balancers`.
To enable `cloud-provider-kind` to function correctly, you’ll need to remove
this label from each control plane node.
For example, in [CNPG Recipe #11]({{< relref "../20240816-kind-multi-node-taints/index.md" >}}),
you can remove the label by running:

```sh
kubectl label node cnpg-control-plane \
  node.kubernetes.io/exclude-from-external-load-balancers-
```

Additionally, if you need to create load balancers for read-only replicas or
any other instances, you can easily do so using `selectorType: ro` for replicas
or `r` for any instance.

## Conclusions

The introduction of service templates in CloudNativePG 1.24 marks a significant
step forward in simplifying and streamlining PostgreSQL deployments in
Kubernetes, especially in DBaaS scenarios. By enabling the easy creation of
custom services, such as `LoadBalancer`, directly within your PostgreSQL
`Cluster` resource, this feature reduces complexity and enhances flexibility in
managing database services across different environments.

With the straightforward process demonstrated in this article, you can now
easily expose PostgreSQL databases outside your Kubernetes cluster, ensuring
seamless external access for applications that reside in different clusters or
environments. The combination of `kind` and `cloud-provider-kind` provides a
powerful yet accessible way to test these features locally, making it easier
to adopt and experiment with CloudNativePG’s new capabilities.

This new functionality not only reduces the overhead associated with managing
external database services but also aligns with the growing need for robust,
scalable DBaaS solutions. As Kubernetes continues to evolve as a platform for
running databases, features like service templates in CloudNativePG 1.24 will
play a crucial role in enabling efficient, reliable, and secure database
operations through Infrastructure as Code (IaC).

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Walking Through a Door“](https://commons.wikimedia.org/wiki/File:Walking_Through_a_Door_%283266056756%29.jpg)._

