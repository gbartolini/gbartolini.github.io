---
title: "CNPG Recipe 18 - Getting Started with pgvector on Kubernetes Using CloudNativePG"
date: 2025-06-05T22:42:04+02:00
description: "Set up a PostgreSQL cluster with `pgvector` on Kubernetes using CloudNativePG in a fully declarative and streamlined way"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "pgvector", "database"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_Learn how to set up a PostgreSQL cluster with the `pgvector` extension on
Kubernetes using CloudNativePG—all in a fully declarative way. This article
walks you through the process in just a few minutes, from cluster creation to
extension installation._

<!--more-->

---


[`pgvector`](https://github.com/pgvector/pgvector) has quickly become one of the
most popular PostgreSQL extensions, especially in the context of AI and machine
learning. It introduces native support for vector data types, which are
essential for similarity search, embedding storage, and other AI-driven use
cases.

In this article, I’ll walk you through how to create a PostgreSQL cluster with
`pgvector` support in Kubernetes using [CloudNativePG](https://cloudnative-pg.io/).
As always, we’ll take a fully declarative approach—and it’ll only take a few
minutes.

## Prerequisites

Before you begin, make sure you have a local Kubernetes environment up and
running using [Kind](https://kind.sigs.k8s.io/) and that you’ve installed the
latest version of CloudNativePG. If you haven’t yet, follow the steps in
["CloudNativePG Recipe 1 - Setting up your local playground in minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}})
to get everything ready.

## Step 1: Define the PostgreSQL Cluster

Let’s start by creating a simple, single-instance PostgreSQL cluster named
`pgvector`. You can scale it later depending on your needs.

Create a file named `pgvector.yaml` with the following contents:

```yaml
{{< include "yaml/pgvector.yaml" >}}
```

Then apply it with:

```sh
kubectl apply -f pgvector.yaml
```

## Step 2: Check Cluster Status

Once the cluster is being created, you can monitor its status with the `cnpg`
plugin:

```sh
kubectl cnpg status pgvector
```

## Step 3: Install the `pgvector` Extension

By default, CloudNativePG creates a database and a user both named `app` for
applications (see ["CNPG Recipe 2 -  Inspecting Default Resources in a CloudNativePG Cluster"]({{< relref "../20240307-recipe-inspection/index.md" >}})
for more information).  CloudNativePG also supports a powerful feature: you can
declaratively [define a `Database` resource](https://cloudnative-pg.io/documentation/current/declarative_database_management/)
and specify extensions to be installed in it.

Since `pgvector` is already bundled in the default
[operand container image for PostgreSQL](https://github.com/cloudnative-pg/postgres-containers),
installing it is straightforward. Create a new file named
`pgvector-db.yaml` with the following contents:

```yaml
{{< include "yaml/pgvector-db.yaml" >}}
```

Apply it with:

```sh
kubectl apply -f pgvector-db.yaml
```

You can inspect the new `Database` resource using:

```sh
kubectl get database pgvector-app
```

or:

```sh
kubectl describe database pgvector-app
```

The controller for the `Database` resource transparently manages `CREATE
EXTENSION`, as well as related commands like `ALTER EXTENSION` and `DROP
EXTENSION`, when the resource is modified or deleted.

## Step 4: Verify the Extension

Let’s now connect to the `app` database and confirm that the `vector` extension
is installed:

```sh
kubectl cnpg psql pgvector -- app -c '\dx'
```

You should see output similar to this:

```console
                            List of installed extensions
  Name   | Version |   Schema   |                     Description
---------+---------+------------+------------------------------------------------------
 plpgsql | 1.0     | pg_catalog | PL/pgSQL procedural language
 vector  | 0.8.0   | public     | vector data type and ivfflat and hnsw access methods
(2 rows)
```

## You're All Set

And there you have it—`pgvector` is installed and ready to use in your `app`
database, running inside a PostgreSQL cluster managed by CloudNativePG on
Kubernetes. What you build with it is entirely up to you. If you're just
getting started and want to experiment, head over to the project’s [“Getting Started” guide](https://github.com/pgvector/pgvector?tab=readme-ov-file#getting-started)
for some practical examples.

This setup offers a solid foundation for experimenting with vector-based AI
workloads using Postgres in a cloud-native way.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“It is Elephants“](https://pxhere.com/en/photo/1604154)._

