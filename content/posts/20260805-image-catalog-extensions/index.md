---
title: "CNPG Recipe 26 - Extension image catalogs"
date: 2026-08-06T22:08:58+10:00
description: "CloudNativePG lets a ClusterImageCatalog resolve extension images by name across every currently supported release, removing per-extension image references from every Cluster manifest."
tags: [ "postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "dok", "data on kubernetes", "extensions", "image-catalog", "imagevolume", "pgvector", "postgres18", "operator", "declarative", "immutability", "supply-chain", "upgrades", "high-availability", "tutorial", "guide" ]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_CloudNativePG lets the `ClusterImageCatalog` carry extension images
alongside the operand, a capability every currently supported release
already has, so a `Cluster` manifest only needs to name an extension and
nothing else. This recipe deploys the community's
extension catalog and shows the operator resolving pgvector's image,
paths and dependencies from a single, versioned source of truth per
PostgreSQL major version. More importantly, it is the piece of
infrastructure that turns extension distribution into a real ecosystem:
once an extension lands in the catalog, every Cluster that references it
inherits it for free, with no manifest ever needing to change again._

<!--more-->

---

In [Recipe 22]({{< relref "../20251006-image-catalog/index.md" >}}) I
introduced the officially maintained `ClusterImageCatalog` resources that
decouple a Cluster's operand image from a hardcoded tag. In
[Recipe 23]({{< relref "../20251201-extensions/index.md" >}}) I showed how
the Kubernetes `ImageVolume` feature and PostgreSQL 18's
`extension_control_path` let CloudNativePG mount `pgvector` and PostGIS from
separate, dedicated images, referenced explicitly through `image.reference`
inside the Cluster's `postgresql.extensions` stanza. And in
[a follow-up]({{< relref "../20260307-extensions-contributions/index.md" >}})
about contributing `pg_crash` to the `postgres-extensions-containers`
project, I flagged that CloudNativePG 1.29 was about to fold extension
images directly into image catalogs.

That feature has shipped. This recipe closes the loop: I deploy the
community's extension catalog, reference it from a Cluster, and watch
`postgresql.extensions` collapse from an explicit image reference to a bare
extension name, with the operator resolving everything else from the
catalog entry matching the Cluster's PostgreSQL major version.

## Prerequisites

This builds directly on Recipe 23, so the baseline requirements carry over,
with one meaningful change since December: [ImageVolume](https://cloudnative-pg.io/docs/current/imagevolume_extensions/)
is now generally available and enabled by default on Kubernetes 1.35 and
later. If you are still on 1.33 or 1.34 you need the feature gate; anything
older is out of scope.

- Kubernetes 1.35 or later (or 1.33/1.34 with the `ImageVolume` feature
  gate enabled).
- A container runtime with `ImageVolume` support: containerd 2.1.0+ or
  CRI-O 1.31+.
- CloudNativePG. Extensions in image catalogs landed in 1.29 and are present
  in every release the project currently supports (1.29 and 1.30 as of this
  writing), so any supported CloudNativePG install already has it.
- PostgreSQL 18, for `extension_control_path`.

If your organisation is still on an older PostgreSQL major and needs this
mechanism sooner, the community does not provide `extension_control_path`
or extension image catalogs below PostgreSQL 18. _(Note: at EDB we do, and
we can provide extension images for our versions of Postgres 15 and later
as part of our enterprise offering, for organisations that cannot wait for
a major upgrade to get there.)_

## Kind cluster setup

For the sandbox itself, follow [Recipe 1]({{< relref "../20240303-recipe-local-setup/index.md" >}}):
grab the latest Kind release, which ships a node image with `ImageVolume`
already enabled by default, so no feature gate is needed here,
unlike in Recipe 23. Install the latest stable CloudNativePG following the
[official instructions](https://cloudnative-pg.io/documentation/current/installation_upgrade/).

## Deploying the community extension catalog

[Recipe 22]({{< relref "../20251006-image-catalog/index.md" >}}) covered
installing the community's official operand catalogs.
Today's addition is a companion kustomize target that patches extensions
into the same catalogs:

```bash
kubectl apply -k \
  https://github.com/cloudnative-pg/artifacts/image-catalogs-extensions?ref=main
```

This overlays the base `image-catalogs` resources with a patch that adds an
`extensions` array to the relevant `major` entries of the Debian Trixie and
Bookworm minimal catalogs. Confirm it landed:

```bash
kubectl get clusterimagecatalogs.postgresql.cnpg.io
```

Then inspect one directly:

```bash
kubectl describe clusterimagecatalogs.postgresql.cnpg.io \
  postgresql-minimal-trixie
```

Trimmed to a couple of representative entries (digests shortened, other
extensions and majors snipped):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ClusterImageCatalog
metadata:
  name: postgresql-minimal-trixie
spec:
  images:
    # majors 13 through 17 omitted: no extensions array yet
    - major: 18
      image: ghcr.io/cloudnative-pg/postgresql:18.4-...-minimal-trixie@sha256:...
      extensions:
        - name: pgvector
          image:
            reference: ghcr.io/cloudnative-pg/pgvector:0.8.6-...-18-trixie@sha256:...
        - name: postgis
          image:
            reference: ghcr.io/cloudnative-pg/postgis-extension:3.6.4-...-18-trixie@sha256:...
          ld_library_path:
            - system
          env:
            - name: GDAL_DATA
              value: ${image_root}/share/gdal
            - name: PROJ_DATA
              value: ${image_root}/share/proj
        # ... <snip> pg-crash, pg-ivm, pgaudit, timescaledb-oss, wal2json
```

Only the PostgreSQL 18 entry carries an `extensions` array today. Earlier
majors in the same catalog have none, since `extension_control_path` is a
PostgreSQL 18 feature and extension image catalogs only make sense for the
major versions that support it. The mechanism itself is not tied to 18: the
moment PostgreSQL 19 ships, extending this same catalog to carry a 19 entry
with its own `extensions` array is a matter of building that major, not of
inventing new machinery. Note too that PostGIS keeps its `ld_library_path`
and `env` overrides bundled into the catalog entry itself, so you inherit
the correct GDAL and PROJ paths without repeating them in every Cluster.

## The manifest: cluster and database

Here is Recipe 23's cluster, for comparison, once `pgvector` is added
directly:

```yaml
postgresql:
  extensions:
  - name: pgvector
    image:
      reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
```

And here is today's version, using the catalog instead:

```yaml
{{< include "yaml/pgvector.yaml" >}}
```

The `image.reference` block is gone. `imageCatalogRef` already pins the
Cluster to `postgresql-minimal-trixie` at `major: 18`, so
`postgresql.extensions` only needs to opt in by name; the operator resolves
`pgvector`'s image, `ld_library_path`, `extension_control_path` and
`dynamic_library_path` from the matching catalog entry. If you need a
different build for one cluster, say a newer `pgvector` you are evaluating
early, you can still override any of those fields locally: catalog values
are defaults, not a lock-in.

Extension activation in the database is unchanged from Recipe 23:

```yaml
{{< include "yaml/pgvector-app.yaml" >}}
```

### Verification

Confirm the extension binaries were mounted, exactly as in Recipe 23:

```bash
kubectl exec -ti pgvector-1 -c postgres -- ls /extensions/
```

Confirm the extension is active in the `app` database:

```bash
kubectl cnpg psql pgvector -- app -c '\dx'
```

The interesting new check is the Cluster's resolved status, which shows
exactly what the operator pulled from the catalog:

```bash
kubectl get cluster pgvector \
  -o jsonpath='{.status.pgDataImageInfo}' | jq
```

The output confirms the effective image reference for both the operand and
`pgvector`, resolved from the catalog entry rather than typed anywhere in
the Cluster spec:

```json
{
  "image": "ghcr.io/cloudnative-pg/postgresql:18.4-...-minimal-trixie@sha256:...",
  "majorVersion": 18,
  "extensions": [
    {
      "name": "pgvector",
      "image": {
        "reference": "ghcr.io/cloudnative-pg/pgvector:0.8.6-...-18-trixie@sha256:..."
      }
    }
  ]
}
```

## Why this matters architecturally

Recipe 23 already decoupled the PostgreSQL core from extension binaries.
What it did not decouple was the Cluster manifest from the exact tag or
digest of every extension it uses, and that coupling scales badly: every
extension bump or PostgreSQL major upgrade meant editing every Cluster that
used it. Folding extensions into the catalog fixes that by extending the
separation of concerns Recipe 22 already established for the operand. I
expect this to become the recommended way of managing images in
CloudNativePG going forward, for the operand and for extensions alike,
with direct `imageName` references and explicit `image.reference` entries
becoming the exception rather than the default:

- **Single source of truth per major.** The catalog pins the operand and
  its compatible extension builds together, so you never end up with a
  `pgvector` image built for a different PostgreSQL major, OS or CPU
  architecture than the Cluster it is mounted into. That kind of ABI
  mismatch is exactly the class of bug image catalogs exist to prevent.
- **Separation of concerns, enforced.** The platform or maintainer team
  owns the catalog and its digests; the application team owns the Cluster
  and simply opts in by name. Neither has to touch the other's object to do
  its job.
- **Fleet-wide rollout, for extensions too.** Bumping the catalog already
  triggers a rolling update across every Cluster referencing it, and
  Recipe 22's spread upgrades (`CLUSTERS_ROLLOUT_DELAY`) throttle that
  rollout fleet-wide. An extension patch shipped through the catalog now
  gets the same safe, staggered rollout as an operand patch, instead of
  being a manual, cluster-by-cluster edit.
- **A clean upgrade path across majors.** Moving a Cluster from major 17 to
  18, or from one minimal catalog to the next, only ever means changing
  `imageCatalogRef.major`. The extensions available at that major are
  whatever the catalog says they are, which is a much easier invariant to
  reason about than auditing every `image.reference` by hand.
- **A template, not a mandate.** The community catalog is a `ClusterImageCatalog`
  like any other, so nothing stops an organisation from forking it, pinning
  its own extension builds and digests, and maintaining a private catalog
  that mirrors the same shape. This is exactly the mechanism air-gapped
  deployments need: mirror the images into your own registry, adjust the
  `image.reference` entries, and the Cluster manifests using
  `imageCatalogRef` do not change at all.

## Conclusion: the catalog is the platform

This is the "streamlined future" I pointed to at the end of the
[extensions contributions post]({{< relref "../20260307-extensions-contributions/index.md" >}}):
CloudNativePG 1.29 shipping support for extensions in image catalogs, which
had been tracked in [PR #9781](https://github.com/cloudnative-pg/cloudnative-pg/pull/9781)
at the time. Seven extensions ship through the community catalog today:
`pg-crash`, `pg-ivm`, `pgaudit`, `pgvector`, `postgis`, `timescaledb-oss`
and `wal2json`. That list is not fixed. Every extension that lands in
[`postgres-extensions-containers`](https://github.com/cloudnative-pg/postgres-extensions-containers)
through the [contribution guide](https://github.com/cloudnative-pg/postgres-extensions-containers/blob/main/CONTRIBUTING_NEW_EXTENSION.md)
I walked through with `pg_crash` is a candidate for the next catalog update,
and once it lands there, it reaches every Cluster referencing the catalog
without a single manifest changing.

That is the part I find most significant about this recipe. Extension
contribution, extension distribution and extension consumption used to be
three separate concerns, each with its own manual step. They are now three
stages of the same pipeline: contribute the image, patch the catalog,
name the extension. If you maintain an extension the community relies on,
or want to, the catalog is where your work actually reaches users, with no
downstream manifest ever needing to know it happened.

I have deliberately left one thing untested here: what actually happens when
the catalog bumps `pgvector` to a newer version and a running Cluster has to
follow. I will cover updating an extension through the catalog, end to end,
in a future recipe.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_This article was drafted and refined with the assistance of Claude (Anthropic).
All technical content, corrections and editorial direction are the author's own._

_Cover Picture: ["Elephant tossing soil"](https://www.pickpik.com/elephant-africa-kenya-tsavo-wildlife-safari-animals-534)._
