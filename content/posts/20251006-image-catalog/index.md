---
title: "CNPG Recipe 22 - Leveraging the New Supply Chain and Image Catalogs"
date: 2025-10-06T12:23:56+02:00
description: "Leverage a new, fully-controlled software supply chain and streamlined Image Catalogs for safer, simpler, and more declarative management of PostgreSQL on Kubernetes"
tags:
  - postgresql
  - postgres
  - kubernetes
  - k8s
  - data on kubernetes
  - dok
  - cloudnativepg
  - cnpg
  - supply chain
  - container images
  - image catalogs
  - sbom
  - security
  - devsecops
  - upgrades
  - extensions
  - snyk
  - cosign
  - sigstore
  - tutorial
  - guide
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_This CNPG Recipe explores the latest enhancements to CloudNativePG's software
supply chain and image management. Learn how our new, fully controlled build
process—complete with Snyk scanning, image signing, and SBOMs—delivers smaller,
more secure PostgreSQL images. We also detail how to leverage the newly
streamlined image catalogs for simplified, declarative cluster management and
safer fleet-wide upgrades in Kubernetes._

<!--more-->

---

The container image is the most fundamental building block of a database in
Kubernetes. As the [Data on Kubernetes (DoK) community](https://dok.community/)
continues to grow and mature, managing the source, version, and security of
this supply chain is critical for any production-grade data service. 

That's why I'm thrilled to announce a foundational improvement in how we build
and source the official [PostgreSQL operand images](https://github.com/cloudnative-pg/postgres-containers)
for CloudNativePG.

This evolution significantly enhances security and reliability, improves the
user experience around image management, and paves a more modular future for
PostgreSQL on Kubernetes.

In line with this, we have also converted our [PostGIS container images](https://github.com/cloudnative-pg/postgis-containers)
to follow the same high standards as the main PostgreSQL images.

## Taking Full Control of Our PostgreSQL Images

First, we at CloudNativePG are making a landmark change to the operand images.
We have definitively moved away from using the official `postgres` image from
Docker Hub, which has accompanied the project since it was open-sourced.

Instead, we have transitioned to a **new software supply chain, built from the
ground up with `docker bake`, that is entirely under the control of the
CloudNativePG project**. While the images continue to be hosted at the standard
registry, their origin and build process are now fundamentally more secure and
robust.

This new, transparent, and secure supply chain provides several key guarantees:

- **Vulnerability Scanning:** Every image is continuously scanned for
  vulnerabilities with **Snyk**, allowing us to react faster to newly
  discovered CVEs.
- **Image Signing:** All images are cryptographically signed using
  **sigstore/cosign**. This provides a guarantee that the images you use were
  built by our pipeline and have not been tampered with.
- **Software Bill of Materials (SBOM):** We generate and distribute an SBOM for
  each image, providing a complete inventory of every software component and
  dependency for full transparency.
- **Optimised Multi-Arch Builds:** Our new `docker bake` pipeline is designed
  from the start to efficiently produce multi-architecture images (**amd64**
  and **arm64**), ensuring first-class support for diverse Kubernetes
  environments.

## Image Catalogs, Perfected: A Reliable New Distribution Pipeline

[**Image Catalogs**](https://cloudnative-pg.io/documentation/current/image_catalog/)
have been a powerful feature in CloudNativePG for over two years, allowing you
to decouple your cluster configuration from specific image tags. However, the
responsibility of creating and maintaining the catalog manifests often fell
to you, the user.

Today, we are removing that friction completely. Our new, trusted distribution
pipeline now provides a reliable, central source for these catalogs. Now,
instead of managing these files yourself, you can install the complete,
[officially maintained catalog](https://www.google.com/search?q=https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs)
with a single command:

```sh
# Deploy all supported PostgreSQL version catalogs to your cluster
kubectl apply -k \
  https://github.com/cloudnative-pg/artifacts/image-catalogs?ref=main
```

Once applied, you can verify that the catalogs have been successfully created
in your cluster with the following command:

```sh
kubectl get clusterimagecatalogs.postgresql.cnpg.io
```

You should see an output similar to this, listing all the available catalogue
options with format `postgresql-<type>-<debian_version>`:

```console
NAME                         AGE
postgresql-minimal-bookworm  19s
postgresql-minimal-bullseye  19s
postgresql-minimal-trixie    19s
postgresql-standard-bookworm 19s
postgresql-standard-bullseye 19s
postgresql-standard-trixie   19s
postgresql-system-bookworm   19s
postgresql-system-bullseye   19s
postgresql-system-trixie     19s
```

To inspect a specific catalog and see the exact image versions it contains, you
can use `kubectl describe`:

```sh
kubectl describe clusterimagecatalogs.postgresql.cnpg.io \
  postgresql-minimal-trixie
```

This reveals the mapping between each major PostgreSQL version and the precise,
immutable container image digest that will be used:

```
Name:         postgresql-minimal-trixie
...
Spec:
  Images:
    Image:  ghcr.io/cloudnative-pg/postgresql:16.10-202509290807-minimal-trixie@sha256:f69b49dc63c2988a358c58f8a1311ac98719846f91d8e97186eaf65c7085cf28
    Major:  16
    Image:  ghcr.io/cloudnative-pg/postgresql:17.6-202509290807-minimal-trixie@sha256:f3e24407db6eb8c3c9a7cb433cfe81cbff006ba1f97ae9844a58c7d3cd8048d7
    Major:  17
    Image:  ghcr.io/cloudnative-pg/postgresql:18.0-202509290807-minimal-trixie@sha256:dd7c678167cc6d06c2caf4e6ea7bc7a89e39754bc7e0111a81f5d75ac3068f70
    Major:  18
...
```

## Putting it to Work: Referencing the Catalog in a Cluster

Once the catalogs are installed, using them in your `Cluster` manifest is
simple and powerful. Instead of a hardcoded `imageName`, you can use
`imageCatalogRef` to select both a catalog and a specific major version from
it.

```yaml
{{< include "yaml/angus.yaml" >}}
```

This elegant abstraction allows your manifest to declare its *intent*. In this
case, you're requesting a cluster using the `postgresql-minimal-trixie`
catalog, and pinning it specifically to **major version 18**.

After the cluster is up and running, you can `describe` it to see how the
operator has resolved your request into a specific image digest in the `Status`
section:

```sh
kubectl describe cluster angus
```

Notice how the `imageCatalogRef` from the `Spec` is translated into a concrete
`Image` in the `Status`:

```
...
Spec:
  Image Catalog Ref:
    API Group:  postgresql.cnpg.io
    Kind:       ClusterImageCatalog
    Major:      18
    Name:       postgresql-minimal-trixie
...
Status:
...
  Image:  ghcr.io/cloudnative-pg/postgresql:18.0-202509290807-minimal-trixie@sha256:dd7c678167cc6d06c2caf4e6ea7bc7a89e39754bc7e0111a81f5d75ac3068f70
...
```

## The Grand Finale: Safe, Automated Fleet Upgrades

This improved system truly shines when managing a database fleet at scale. When
you update the Image Catalog in your cluster, all related clusters will be
scheduled for a rolling update. To prevent a "thundering herd" that could
overwhelm your system, you can control the rollout globally.

This feature, called **spread upgrades**, is configured in the operator's main
`ConfigMap`. By setting the `CLUSTERS_ROLLOUT_DELAY` variable, you instruct the
operator to wait a specific number of seconds before starting the update on the
next cluster.

For example, to set a 2-minute delay between each cluster update:

```yaml
{{< include "yaml/operator-config.yaml" >}}
```

This is a powerful and simple way to ensure a safe, controlled, and completely
automated rollout of updates across your entire database fleet.

## A More Declarative and Modular Future

These improvements—a fully controlled supply chain and a reliable distribution
pipeline for catalogs—are more than just operational conveniences.
They are foundational steps towards a more secure and modular architecture for
running PostgreSQL on Kubernetes. Our ultimate goal is to ship "minimal"
PostgreSQL images containing only the core database engine.

This vision is realised through another powerful feature called "extension
image volumes". Instead of bundling every possible extension into a single,
monolithic image, each extension is packaged in its own separate image.

A newborn project, [PostgreSQL Extension Containers](https://github.com/cloudnative-pg/postgres-extensions-containers),
will contain these images.

When needed, CloudNativePG dynamically loads it into your PostgreSQL pod.

This combined approach is the future:

- **Enhanced Security:** Your core database has a **smaller surface attack**.
- **Modularity and Flexibility:** Manage, version, and update extensions
  independently of the PostgreSQL engine.

The image catalogs are the control plane that makes this modular ecosystem
possible, providing the robust, declarative mechanism to manage the entire
suite of components that power your applications.

## Get Started Today

First, I want to thank the entire CloudNativePG team for completing this epic
enhancement, which we started at the beginning of the year. I am really proud
of the result we have achieved from every aspect: operations, security, and
extensibility.

The fact that the [PostgreSQL 18 minimal image is now ~230MB]({{< relref "../20250926-postgresql-18/index.md" >}})
—45% smaller than the equivalent for PostgreSQL 17—is a major step forward. The
image catalogue artifacts are also an important achievement for
standardisation, simplifying integration into any deployment.

I encourage you to adopt this new, simplified workflow for image catalogs
today. You can get started by applying them from our
[`artifacts` repository](https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs).

For a deeper dive, check out the official documentation on [image catalogs](https://cloudnative-pg.io/documentation/current/image_catalog/)
and [spread upgrades](https://cloudnative-pg.io/documentation/current/installation_upgrade/#spread-upgrades).

To see where this is headed, I invite you to read my previous article on
["The Immutable Future of PostgreSQL Extensions"]({{< relref "../20250303-volume-source-extension-control-path/index.md" >}})
and the official docs on [extension image volumes](https://cloudnative-pg.io/documentation/current/imagevolume_extensions/).

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!
