---
title: "CNPG Recipe 23 - Managing extensions with ImageVolume in CloudNativePG"
date: 2025-12-01T21:35:11+01:00
description: "Leveraging the Kubernetes `ImageVolume` feature and PostgreSQL 18's `extension_control_path`, this article demonstrates the CloudNativePG method for declaratively managing extensions like `pgvector` and PostGIS from separate container images, marking the culmination of a multi-year vision to decouple the database core from extension distribution."
tags: [ "postgresql", "kubernetes", "cloudnativepg", "pgvector", "postgis", "imagevolume", "declarative", "extensions", "immutability", "postgres18", "operator", "database", "cnpg", "dok", "extension_control_path" ]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_Say goodbye to the old way of distributing Postgres extensions as part of the
main pre-built operand image. Leveraging the Kubernetes `ImageVolume` feature,
CloudNativePG now allows you to mount extensions like `pgvector` and
PostGIS from separate, dedicated images.
This new declarative method completely decouples the PostgreSQL core from the
extension binaries, enabling dynamic addition, easier evaluation, and
simplified updates without ever having to build or manage monolithic custom
container images._

<!--more-->

---

In a [previous post]({{< relref
"../20250303-volume-source-extension-control-path/index.md" >}}), I made the
case for the **immutable future of PostgreSQL extensions** on Kubernetes.
Traditionally, achieving immutability meant building large, custom container
images for the Postgres operand with every extension needed.

Before the method I am about to show you, the common approach for extensions like
`pgvector` was to use the `standard` CNPG image, which already came
pre-packaged with only a few extensions—a method I detailed in my article on
[getting started with `pgvector` on Kubernetes]({{< relref "../20250926-postgresql-18/index.md" >}}).

Now, I want to show you a groundbreaking, more flexible approach that I believe
represents the *true* future of extension management: a moment that marks the
beginning of the end of a multi-year vision we've had at EDB and, previously,
at 2ndQuadrant.

This new flexibility is unlocked by the latest crucial steps: the combination
of PostgreSQL 18's `extension_control_path` GUC (Grand Unified Configuration
variable) and the Kubernetes `ImageVolume` feature. We're leveraging this with
CloudNativePG to mount extensions from dedicated container images. Notably,
`pgvector` and PostGIS are the first set of extension images officially
released by the community through the [`postgres-extensions-containers` project](https://github.com/cloudnative-pg/postgres-extensions-containers).

This allows us to use the small, official `minimal` PostgreSQL images while
seamlessly integrating complex extensions like `pgvector` and PostGIS.

## Prerequisites: PostgreSQL 18 and Kubernetes' `ImageVolume`

Before diving into the manifests, I must stress the technical requirements for
this approach. It relies on Kubernetes' capability to expose an entire
container image as a volume, which CNPG then mounts into the PostgreSQL pod.

This functionality requires Kubernetes 1.33 or later because it depends on the
`ImageVolume` feature. This feature is not yet enabled by default, but it is
expected to be generally available and enabled by default in Kubernetes 1.35
(available this month, December 2025).

If you are using Kind for your local development environment, you must
explicitly enable this feature gate when creating your cluster, like in the
example below:

```bash
(cat << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
featureGates:
  ImageVolume: true
EOF
) | kind create cluster --config -
```

For our demonstration, I will be using **PostgreSQL 18**.
Note that to run these manifests, you must also have the latest stable version
of CloudNativePG installed in your Kubernetes cluster; instructions can be
found in the official [CloudNativePG documentation](https://cloudnative-pg.io/documentation/preview/installation_upgrade/).


## Starting with the minimal CNPG cluster

I always recommend starting simple. We begin with the most basic, lightweight
CNPG Cluster definition. I am using the official CNPG `minimal` image for
PostgreSQL (which I have written about previously in my piece on
[leveraging the new CNPG supply chain and image catalogs]({{< relref "../20251006-image-catalog/index.md" >}}))
for PostgreSQL 18 (which you can learn more about
[running PostgreSQL 18 today on Kubernetes]({{< relref "../20250605-pgvector/index.md" >}})).

```yaml
{{< include "yaml/01.yaml" >}}
```

This cluster is perfectly ready to serve basic PostgreSQL operations.
This image adheres to the minimal design principle: at just 260MB, it contains
only the core database binaries, serving as a clean, dependency-free foundation
for our immutable extension strategy.
However, if you attempt to run `CREATE EXTENSION vector;` right now, the
command will fail because the required extension control and shared object
(`.so`) files are not present in the `minimal` base image.

## Introducing `pgvector` via a dedicated image

Instead of switching to a heavy, custom `imageName`, I introduce the new
`postgresql.extensions` block. This is where the magic happens. I am
instructing CloudNativePG to find a separate image (which, for `pgvector`, weighs
only **613KB**) containing the compiled `pgvector` binaries and mount it into the
PostgreSQL container using `ImageVolume`.

### The manifest

```yaml
{{< include "yaml/02.yaml" >}}
```

### Verification: the extension is ready

Once you apply the manifests above, CloudNativePG handles both mounting the
binary files via `ImageVolume` and running the necessary `CREATE EXTENSION`
SQL.

First, let's confirm the `pgvector` binaries have been successfully mounted
into the pod's filesystem. I'm targeting the primary pod (assuming the name
follows the pattern `angus-1`) and listing the contents of the
mounted `/extensions/` directory:

```bash
kubectl exec -ti angus-1 -c postgres -- ls /extensions/
```

The output confirms the extension directory is present, mounted from the
separate extension image:

```
pgvector
```

Next, we verify that the extension is active and ready in the `app` database:

```bash
kubectl cnpg psql angus -- app -c '\dx'
```

The output confirms the declarative process was successful:

```
                                      List of installed extensions
  Name   | Version | Default version |   Schema   |                  Description
---------+---------+-----------------+------------+------------------------------------------------------
 plpgsql | 1.0     | 1.0             | pg_catalog | PL/pgSQL procedural language
 vector  | 0.8.1   | 0.8.1           | public     | vector data type and ivfflat and hnsw access methods
(2 rows)
```

### What I have achieved here

1. `Cluster.spec.postgresql.extensions`: I have registered the `pgvector`
   extension by referencing a specific extension image. This image holds only
   the compiled binaries for `pgvector`.

2. `ImageVolume` in action: CloudNativePG intelligently mounts the contents of
   `ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie` directly into the
   PostgreSQL pod's file system, ensuring the necessary binaries are available
   and read-only. Underneath, this is achieved by leveraging the
   `extension_control_path` GUC, a key feature introduced in PostgreSQL 18,
   which allows the database to locate the necessary extension control files
   outside of the traditional installation directories.

3. `Database.spec.extensions`: This resource handles the final, declarative
   activation. I instruct PostgreSQL to run `CREATE EXTENSION vector VERSION '0.8.1';`.
   This is key: CloudNativePG manages this command declaratively,
   meaning I never have to connect and run SQL myself. Furthermore, the
   `version` field is crucial; by simply applying a new image and changing this
   value, CNPG orchestrates the PostgreSQL update path (provided the extension
   itself supports the upgrade).

This cleanly decouples the PostgreSQL core from the extension binaries,
providing immutability without the custom image maintenance headache.

## Scaling up: integrating multiple complex extensions

The real power of this method becomes apparent when dealing with complex,
interdependent extensions like PostGIS. PostGIS requires several companion
extensions and shared library dependencies, which are notoriously difficult to
manage manually.

I can easily add PostGIS by simply listing it under `extensions`. Note the
inclusion of the `ld_library_path` configuration for PostGIS; this is a vital
element that ensures its dynamic linker paths are correctly configured for
maximum reliability. Finally, I define all the necessary PostGIS-related
companion extensions in the `Database` resource:

```yaml
{{< include "yaml/03.yaml" >}}
```

After applying this full manifest, I encourage you to check the validation
commands from the previous section again. You'll find that the `/extensions/`
directory now contains both `pgvector` and the PostGIS files, and the `\dx`
output confirms that all **PostGIS** dependencies, including
`postgis_topology`, have been successfully created in the database.

## Summary

The ability to mount extensions from separate images using `ImageVolume`
with CloudNativePG 1.27+ is a game-changer. It allows us to:

- **Decouple:** upgrade the core PostgreSQL image independently of the
  extension images. This also applies to the build project (which is very
  important for us maintainers and contributors of CloudNativePG).
- **Dynamic and easy evaluation:** extensions can be added dynamically to an
  existing cluster, making the evaluation of new features fast and
  frictionless.
- **Maintain small images:** my base `imageName` remains small, secure, and
  simple.
- **Ensure consistency:** CloudNativePG handles all the complex volume mounting
  and dependency mapping, guaranteeing a consistent, immutable environment
  across the entire cluster without needing custom Dockerfile builds.

Finally, I want to mention that we are currently working to standardise the way
we create these extension images in the [`postgres-extensions-containers` repository on GitHub](https://github.com/cloudnative-pg/postgres-extensions-containers).

The goal of this project (see [issue #15](https://github.com/cloudnative-pg/postgres-extensions-containers/issues/15))
is to scale up the number of supported extensions by providing a framework
that can be used by more contributors to add extensions they like, as long as
they become component owners/maintainers for that extension in the
CloudNativePG community.
I will cover our progress on this project in a future post.

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

