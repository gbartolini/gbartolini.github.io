---
title: "From proposal to PR: how to contribute to the new CloudNativePG extensions project"
date: 2026-03-07T17:36:35+11:00
description: "A step-by-step guide on contributing PostgreSQL extensions to the CloudNativePG ecosystem using modern build tools and the new Image Volume feature."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "extensions", "pg_crash", "chaos engineering"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In this article I walk you through the journey of adding the `pg_crash`
extension to the new CloudNativePG extensions project. It explores the
transition from legacy standalone repositories to a unified, Dagger-powered
build system designed for PostgreSQL 18 and beyond. By focusing on the *Image
Volume* feature and minimal operand images, the post provides a step-by-step
guide for community members to contribute and maintain their own extensions
within the CloudNativePG ecosystem._


<!--more-->

---

At CloudNativePG, we recently reached a milestone in how we manage PostgreSQL
extensions. With the Kubernetes **Image Volume** feature and the new
`extension_control_path` parameter in PostgreSQL 18, we finally have a scalable
way to provide the community with trusted, immutable extension images.
This critical advancement is the result of amazing work by my colleagues at
EDB, both for CloudNativePG and PostgreSQL. This led to the creation of the
[`postgres-extensions-containers`](https://github.com/cloudnative-pg/postgres-extensions-containers)
project.

But a repository is only as good as its contribution workflow, and only time
will tell.

## The birth of a unified ecosystem

Making this project a reality was a significant undertaking. If you are
interested in the technical roadmap, you can explore the [GitHub Epic (Issue #15)](https://github.com/cloudnative-pg/postgres-extensions-containers/issues/15),
which tracks the features and tasks we implemented to make community
contributions possible.

As maintainers, our first priority was ensuring a seamless upgrade path for our
existing users. Before opening the doors to community contributions, we
migrated and stabilised the key extensions that we already maintain:

- `pgAudit` and `pgvector`: currently part of the `standard` and `system`
  images in the [`postgres-containers`](https://github.com/cloudnative-pg/postgres-containers)
  project.
- `PostGIS`: currently maintained in the dedicated
  [`postgis-containers`](https://github.com/cloudnative-pg/postgis-containers)
  project.

It is worth noting that we have omitted `pg_failover_slots` from this new
project. This is because PostgreSQL 18 and CloudNativePG 1.27+ now provide
native support for failover slots, making the external extension redundant for
the future.

We are also shifting our strategy regarding operand containers: the `system`
and `PostGIS` operand images will eventually disappear once PostgreSQL 17 is
phased out in November 2029. For PostgreSQL 18 and beyond, this new unified
repository is the official home.
While the `standard` image will remain to serve users requiring locale support
and specific libraries, the ecosystem is converging towards **minimal images**.

By centralising these extensions, we have decoupled their lifecycle from the
main PostgreSQL engine images. This allows us to update an extension or patch a
vulnerability without forcing a rebuild of the entire PostgreSQL operand
image. It is a massive win for operational stability and security.

## The case study: pg_crash

To "dogfood" our new contribution process, I chose to migrate `pg_crash`. This
extension is a disruptive tool designed for Chaos Engineering; it
randomly or periodically terminates PostgreSQL processes to verify that
CloudNativePG properly detects failures and performs failovers.

I strongly discourage using it in production, unless you are deliberately chaos
engineering your infrastructure (which, in fact, is the proper way to perform
chaos engineering). However, for most users, it serves as the ultimate "fire
drill" for testing resilience in staging environments.

By distributing the `pg_crash` extension image, we can successfully dismiss the
old, standalone [`pgcrash-containers`](https://github.com/cloudnative-pg/pgcrash-containers)
project and, at the same time, provide an example for future contributors to follow.

## The journey: following the guide

I used our new
[`CONTRIBUTING_NEW_EXTENSION.md`](https://github.com/cloudnative-pg/postgres-extensions-containers/blob/main/CONTRIBUTING_NEW_EXTENSION.md)
guide as my map. Here is how the journey looked.

### Package discovery

Before writing code, I had to ensure the package was available in the PGDG
(PostgreSQL Global Development Group) repositories. I ran a "disposable"
container to search for it:

```sh
docker run -u root -ti --rm ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
# apt update && apt search pg-crash
```

### Scaffolding the extension

We use [Dagger](https://dagger.io) to automate the mundane tasks of
building and testing. One command created the entire directory structure for
me:

```bash
task create-extension NAME=pg-crash
```

This generated the `metadata.hcl`, `Dockerfile`, and a template `README.md`. My
job was to fill in the "TODOs" to ensure the extension correctly copied the
`.so`, `.sql`, and `.control` files into the scratch image.

### The local feedback loop

One of the most satisfying parts of the workflow is the local testing
environment. I could bake the image and see it running in a real Kubernetes
cluster on my laptop:

```bash
task e2e:test:full TARGET="pg-crash"
```

The framework provides basic smoke tests to verify that the extension image can
be deployed in a CNPG cluster and installed both in the system and, if
applicable, in a database via `CREATE EXTENSION`.
If an extension requires more rigorous validation, you can submit additional
specific tests using the Chainsaw framework.

### Manual verification

Once the automated tests passed, I performed a manual "sanity check". I
exported the Kubeconfig, identified the image tag using tools like `skopeo`,
and deployed a 3-instance cluster to watch `pg_crash` trigger a real failover.
Seeing the orchestrator respond exactly as expected is the ultimate validation.

## Navigating licensing

During the PR process
([#126](https://github.com/cloudnative-pg/postgres-extensions-containers/pull/126)),
we refined our licensing policy. Since we redistribute unmodified PGDG
packages, we confirmed that the PostgreSQL License is CNCF-compliant.
For other open-source licenses, such as FSF-approved (GPL), we established a
case-by-case review process to ensure the legal integrity of the project.

## Conclusion: join the movement

With thew conversion of `pg_crash` to an image volume extension, we have turned
a standalone maintenance burden into a community-ready template.

The [`postgres-extensions-containers`](https://github.com/cloudnative-pg/postgres-extensions-containers)
project represents a unique opportunity for everyone to contribute to
CloudNativePG and maintain one or more extensions for the years to come.
By maintaining these images, you are helping build the most robust and flexible
PostgreSQL ecosystem in the cloud-native world.

If you want to dive deeper into the technical mechanics of how these extensions
are used, I encourage you to read my previous blog post:
[CNPG Recipe 23: Managing extensions with ImageVolume in CloudNativePG]({{< relref "../20251201-extensions/index.md" >}}).

Furthermore, the future of extension management is becoming even more
streamlined; CloudNativePG 1.29 introduces [support for extensions in image catalogs](https://github.com/cloudnative-pg/cloudnative-pg/pull/9781),
a feature that makes the distribution,discovery and usage of these
community-maintained images much easier.

Finally, I want to thank EDB and EDB's customers for supporting us in this
endeavour. This project has been nearly two years in the making, and your
support is what allows us to keep making Postgres better for the years to come
in Kubernetes.

_Are you ready to contribute? Check out the
[Contribution Guide](https://github.com/cloudnative-pg/postgres-extensions-containers/blob/main/CONTRIBUTING_NEW_EXTENSION.md)
and let's build the future of cloud-native PostgreSQL together!_

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

