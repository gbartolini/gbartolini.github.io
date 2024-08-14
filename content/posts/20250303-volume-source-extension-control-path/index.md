---
title: "The Immutable Future of PostgreSQL Extensions in Kubernetes with CloudNativePG"
date: 2025-03-03T11:38:14+01:00
description: "How managing Postgres extensions in Kubernetes will change"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "extensions", "container images", "sbom", "pgvector", "imagevolume", "extension_control_path"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_Managing extensions is one of the biggest challenges in running PostgreSQL on
Kubernetes. In this article, I explain why I believe [CloudNativePG](https://cloudnative-pg.io/)
—now a CNCF Sandbox project—is on the verge of a breakthrough.
Two important new features for both PostgreSQL and Kubernetes—the
`extension_control_path` option and image volumes—will guarantee immutability
to extension container images._

<!--more-->

---

A core principle of Kubernetes is the immutability of container images. With
[CloudNativePG, we embraced this approach from day one](https://www.enterprisedb.com/blog/why-edb-chose-immutable-application-containers),
firmly adhering to best practices such as immutable infrastructure,
Infrastructure as Code (IaC), and shifting security left.

This immutability means that PostgreSQL container images must remain read-only
to ensure security and reliable change management. However, this approach
clashes with one of PostgreSQL’s greatest strengths: **extensibility**.
Extensions have indeed played a crucial role in PostgreSQL’s rise as the most
popular and versatile database engine.

While core extensions like `pg_stat_statements` and `postgres_fdw` are
included in every [PostgreSQL operand image](https://github.com/cloudnative-pg/postgres-containers),
third-party extensions—such as PostGIS, TimescaleDB, and pgvector—are separate
projects and are not bundled with PostgreSQL by default.

In traditional virtual machine (VM) deployments, extensions can be installed at
runtime using the package manager of the Linux distribution. However, with
CloudNativePG, modifying the container image is not possible; you must rely on
declarative configuration and pre-existing images. Additionally, deployment is
only part of the challenge: updates as part of Day 2 operations are usually
handled case-by-case, impacting scalability and maintainability of
infrastructures and applications sensibly.

## The Current Approach: Pre-built Operand Images

Until now, the only way to run third-party extensions with CloudNativePG (and
most PostgreSQL operators) without breaking immutability has been to embed them
in the operand image. However, this approach has significant downsides:

- **Increased image size and footprint** – The more extensions included, the
  larger the image.
- **Rigid extension selection** – Users are often left frustrated because:
    - Their required extension isn’t included.
    - They want a lighter image without unnecessary extensions.
    - They don’t want specific libraries due to CVEs or security concerns.
- **Operational complexity** – Users must maintain custom images, as outlined
    in our guide on [creating container images](https://cloudnative-pg.io/blog/creating-container-images/) and
    following our [image requirements](https://cloudnative-pg.io/documentation/current/container_images/).

Not everyone has the resources or expertise to do this. Compliance is another
critical factor.

We have long been exploring ways to enable dynamic loading of extensions in
CloudNativePG. I recall insightful discussions with **Tembo**, an early
[adopter of CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md),
about reserving a volume for dynamically installing third-party extensions.
However, we decided not to pursue that idea, as it violated our immutability
principle (Tembo later pursued their [Trunk](https://github.com/tembo-io/trunk)
project).

To achieve dynamic extension loading **without** breaking immutability, we
needed improvements in **both PostgreSQL and Kubernetes**.

Fortunately, these improvements are finally happening.

## What’s Missing in PostgreSQL?

Currently, PostgreSQL requires extensions to be installed in a system
directory, such as `/usr/share/postgresql/17/extension`, where it looks for
[extension control files](https://www.postgresql.org/docs/current/extend-extensions.html).

In traditional setups, Linux package managers (Debian/RPM) install extension
packages, placing control files in this directory. While this works in a
mutable environment, it is incompatible with an immutable setup like
CloudNativePG, where the system directory is **read-only** for security.

To overcome this limitation, PostgreSQL needs to support alternative extension
locations. This is precisely what the patch developed by my [EDB](https://enterprisedb.com) colleagues
Peter Eisentraut, Andrew Dunstan, and Matheus Alcantara and
[proposed for PostgreSQL 18 ](https://commitfest.postgresql.org/patch/4913/)
aims to do. The patch is based on an initial work by Christoph Berg.
It is part of a broader [discussion started by David Wheeler](https://www.postgresql.org/message-id/flat/E7C7BFFB-8857-48D4-A71F-88B359FADCFD@justatheory.com)
(Tembo), which I contributed to to align it with Kubernetes' immutability
needs. We further refined this direction during in-person conversations at
PostgreSQL Europe in Athens in October 2024
([David wrote a great recap here](https://justatheory.com/2024/11/rfc-extension-packaging-lookup/)).

### Introducing `extension_control_path`

The proposed patch introduces a new PostgreSQL configuration option (GUC),
`extension_control_path`, which allows users to specify additional
directories for extension control files. It is set to `$system` by default,
but users can define multiple paths—just like other path-like configuration
options in PostgreSQL.

Combined with `dynamic_library_path`, this feature enables PostgreSQL to
locate control files and shared libraries from multiple directories, **breaking
free from the single system-wide location constraint**.

I hope this patch is merged into PostgreSQL and becomes part of **PostgreSQL
18**, ensuring that future versions fully support this approach.

## What’s Missing in Kubernetes?

Even with PostgreSQL supporting multiple extension paths, we still need a way
to dynamically mount extensions into a running CloudNativePG cluster **without
modifying the primary container image**. This is where Kubernetes is stepping
up.

### Introducing `ImageVolume` resources

The [ImageVolume feature](https://kubernetes.io/blog/2024/08/16/kubernetes-1-31-image-volume-source/)
was introduced as an **alpha feature in Kubernetes 1.31** and is expected to
reach beta soon. Its goal is to be promoted to a beta release state in
Kubernetes 1.33.

This feature allows us to mount a container image as a **read-only and
immutable volume** inside a running pod. It will enable PostgreSQL extensions
that are packaged as **independent OCI-compliant container images** to be
mounted inside CloudNativePG clusters at a known directory (e.g.,
`/extensions/<EXTENSION_NAME>`).

At this point, all we’ll need to do is set the ``extension_control_path`` and
``dynamic_library_path`` options accordingly. An operator like CloudNativePG
can automate this process, making it seamless for users. The same approach can
be repeated multiple times, once per required extension.

Image extension images at that point must be compatible with the Postgres base
image that the CloudNativePG has deployed (for example, the same distribution
and architecture).


## How We Tested These Features in CloudNativePG

Although we weren’t directly involved in developing these new PostgreSQL
features, **some of us at CloudNativePG contributed to testing the
corresponding patch**.

I want to give special thanks to **Niccolò Fei** for his outstanding work
validating the patch developed by Peter, Andrew, and Matheus. This includes
patches for the CloudNativePG operator and extension images.

Our testing focused on:

- **Streamlining the build process** for PostgreSQL operand images that
  incorporate patches from the PostgreSQL commit fest (for details, see my
  [previous article](https://www.gabrielebartolini.it/articles/2024/09/how-to-test-a-postgresql-commitfest-patch-in-kubernetes/)).
- **Developing a pilot patch for CloudNativePG** to declaratively add
  PostgreSQL extensions via a container image. The operator mounts the image as
  an `ImageVolume`, automatically configuring `extension_control_path` and
  `dynamic_library_path`.
  See [CloudNativePG PR #6546](https://github.com/cloudnative-pg/cloudnative-pg/pull/6546).
- **Creating self-contained extension images**, such as one for `pgvector`.

### Lightweight Extension Images

Focusing on the last point, Niccolò proposed a
[Dockerfile for pgvector](https://github.com/EnterpriseDB/pgvector/blob/dev/5645/Dockerfile.cnpg)
that produces a **minimal** image—containing only the `lib` and `share`
directories—at just **1.6MB**.

To inspect its contents, use:

```sh
dive ghcr.io/cloudnative-pg/pgvector-18-testing:latest
```

### Deploying Extensions Declaratively

To illustrate the proposed solution, consider this example (note: the format is
still in alpha and may change):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgresql-with-extensions
spec:
  instances: 1
  # This points to the temporary build of the commit fest patch
  imageName: ghcr.io/cloudnative-pg/postgresql-trunk:18-cf-4913
  postgresql:
    extensions:
      - name: pgvector
        image:
          reference: ghcr.io/cloudnative-pg/pgvector-18-testing:latest
  storage:
    storageClass: standard
    size: 1Gi
```


The key addition is the `.spec.postgresql.extensions` section, where users can
define extensions and their corresponding images (each an `ImageVolume`
resource). This configuration can be updated dynamically.

### What Happens Under the Hood

When an extension image is specified:

1. The operator triggers a rolling update, starting with replicas.

2. Each referenced image is mounted as a **read-only volume** using Kubernetes'
   `ImageVolume` resource.

3. In this example, `ghcr.io/cloudnative-pg/pgvector-18-testing:latest` is
   mounted on `/extensions/pgvector`.

4. CloudNativePG updates `dynamic_library_path` and `extension_control_path` to
   include the `/extensions/pgvector/lib` and `/extensions/pgvector/share`
   directories, respectively.

Once deployed, you can verify the extension’s availability:

```sql
postgres=# SELECT * FROM pg_available_extensions WHERE name = 'vector';
-[ RECORD 1 ]-----+-----------------------------------------------------
name              | vector
default_version   | 0.8.0
installed_version |
comment           | vector data type and ivfflat and hnsw access methods
```

**Important:** This feature is not yet available out of the box. To use `ImageVolume`, you need:

- **Kubernetes 1.31+** with the [ImageVolume feature gate](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/)
  enabled.
- **CRI-O** as the container runtime (*containerd support has been merged but
  is not yet available*).

We applied the same approach to **PostGIS during our pilot project**, creating
a self-contained extension image. The method proved effective even for complex
extensions.

## Conclusion

This is just the beginning. This initiative marks the first iteration toward a
new approach to managing PostgreSQL extensions in Kubernetes—bridging the gap
between extension developers and consumers. The most important takeaway is that
we’re heading in the right direction, opening the door to new possibilities and
allowing the best solutions to emerge through exploration.

While PostgreSQL’s `extension_control_path` and Kubernetes'
`ImageVolume` feature are fundamental pieces, there’s another
critical component: **the distribution of PostgreSQL extensions**.

It's time for PostgreSQL extension developers to embrace **OCI images as
first-class artifacts**, alongside traditional RPM and Debian packages.
Ideally, every extension should provide a self-contained image for mainstream
Linux distributions. Whether these images are built from existing packages or
directly from source (e.g., via `Makefile`) is a decision best left to those
with deeper expertise in the packaging ecosystem.

With **PostgreSQL 18** supporting configurable extension paths and **Kubernetes
1.33** introducing `ImageVolume`, CloudNativePG is entering a **new era of
dynamic, immutable, and scalable extension management**. By packaging
extensions as independent OCI-compliant images, we can finally **decouple
PostgreSQL operand images from extensions**, keeping them minimal and flexible.
This unlocks several key benefits:

- **Install third-party extensions dynamically**—no need to rebuild container
  images.
- **Facilitate testing and validation of extensions**
- **Simplify PostgreSQL extension upgrades** without affecting the core
  database image.
- **Ensure strict immutability** while enhancing security, change management,
  scalability, and maintainability.

This is a game-changer for **CloudNativePG** and the broader
**PostgreSQL-on-Kubernetes ecosystem**.

The future of PostgreSQL extensions in Kubernetes is **immutable, yet
flexible—just as it should be**.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [“Sofyan Efendi Dipinggiran Sungai“](https://commons.wikimedia.org/wiki/File:Sofyan_Efendi_Dipinggiran_Sungai_IMG_3249.jpg)._

