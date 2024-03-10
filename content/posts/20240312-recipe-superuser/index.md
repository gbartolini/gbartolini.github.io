---
title: "CloudNativePG Recipe 3 - What!?! No superuser access?"
date: 2024-03-11T21:46:53+01:00
description: "Understand why superuser access is disabled by default with CloudNativePG and how to enable if you can't do without it"
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "app", "microservice database", "superuser", "alter system", "security", "pola", "polp"]
cover: cover.png
thumb: thumb.png
draft: false
---

_Explore the secure defaults of a PostgreSQL cluster in this CloudNativePG
recipe, aligning with the principle of least authority (PoLA). Our commitment
to security and operational simplicity shines through default configurations,
balancing robust protection with user-friendly settings. Advanced users can
customize as needed. The article navigates default intricacies, PostgreSQL
Host-Based Authentication, and the scenarios for enabling superuser access. We
also touch on the careful use of the `ALTER SYSTEM` command, emphasizing our
dedication to secure and simple operations._

<!--more-->

---

If you've explored my [latest recipe]({{< relref "../20240307-recipe-inspection/index.md">}}),
you may have noticed the absence of mention about the `postgres` user,
specifically its password. The reason is straightforward – by default, this
user has no network access, and its password is set to `NULL` within the
database server.

Security by default is a cornerstone principle guiding CloudNativePG. Our
commitment revolves around crafting a system that, in its default
configuration, deploys a PostgreSQL server with the utmost security, aligning
with our current standards. This commitment includes implementing PoLA, the
principle of least authority, ensuring that default access privileges are
minimal. Defaults hold significant weight, especially in setups where
simplicity is preferred and the easiest path is often taken.

For those well-versed in PostgreSQL and Kubernetes, desiring more control over
their Postgres cluster, CloudNativePG offers the freedom to customize any
default value without constraints. No strings attached!

In [my initial recipe]({{< relref "../20240303-recipe-local-setup/index.md">}}#create-your-first-postgresql-cluster),
we delved into convention over configuration using the `cluster-example`
example. Now, let's examine the resulting resource after the mutating webhook
has applied some default values:

```sh
kubectl get cluster -o yaml cluster-example \
  | grep -i superuser
```

Resulting in:

```console
  enableSuperuserAccess: false
```

Upon inspection, it's evident that the default setting for
`enableSuperuserAccess` is `false`, a primary security measure adopted by
CloudNativePG in line with the PoLA philosophy. This default configuration
essentially restricts network connections via the `postgres` user, a user
crucial for the operator to coordinate and manage a PostgreSQL server through
the [instance manager](https://cloudnative-pg.io/documentation/current/instance_manager/).

To gain insight into the configuration of PostgreSQL Host-Based Authentication,
we can execute the following query:

```sh
kubectl exec -ti -c postgres cluster-example-1 \
  -- psql -c 'SELECT type, database, user_name, address,
              auth_method, options FROM pg_hba_file_rules
              ORDER BY rule_number'
```

The result provides a snapshot of the authentication rules:

```
  type   |   database    |        user_name        | address |  auth_method  |         options
---------+---------------+-------------------------+---------+---------------+--------------------------
 local   | {all}         | {all}                   |         | peer          | {map=local}
 hostssl | {postgres}    | {streaming_replica}     | all     | cert          | {clientcert=verify-full}
 hostssl | {replication} | {streaming_replica}     | all     | cert          | {clientcert=verify-full}
 hostssl | {all}         | {cnpg_pooler_pgbouncer} | all     | cert          | {clientcert=verify-full}
 host    | {all}         | {all}                   | all     | scram-sha-256 |
(5 rows)
```

The demonstrated access assumes sufficient permissions to reach the PostgreSQL
containers, leveraging the `peer` authentication method. In this context, as
the container operates under the `postgres` user, the connection is established
using the `postgres` database user. By default, this is the sole access granted
as `postgres`, strictly governed by Kubernetes RBACs.

The final default rule stipulates that, with a password in place, you can
connect with any user from anywhere to any database, using both TLS and non-TLS
connections. If this default configuration isn't suitable, you have the
flexibility to enhance security by adding a more rigorous rule in the `pg_hba`
file. For additional details, refer to ["The `pg_hba` section"](https://cloudnative-pg.io/documentation/current/postgresql_conf/#the-pg_hba-section).

An added security benefit is that the `postgres` user within the database has a
password set to `NULL`, effectively thwarting any unauthorized authentication
attempts. This precautionary measure aligns with CloudNativePG's commitment to
robust security practices by default.

```sh
kubectl exec -ti -c postgres cluster-example-1 \
  -- psql -c 'SELECT usename FROM pg_shadow
                WHERE passwd IS NULL'
```

The absence of default passwords for both the `postgres` and
`streaming_replica` users is noteworthy:

```console
      usename
-------------------
 postgres
 streaming_replica
(2 rows)
```

This holds significant security implications. By not assigning default
passwords, CloudNativePG enhances the overall security posture of the system.
This practice reduces potential vulnerabilities, aligning with the platform's
dedication to robust security measures.

## Enabling superuser access

Surprisingly ( _for me ;)!_ ), there are cases where the `postgres` user
becomes indispensable. This need commonly arises from either of the following:

- **Lift-and-Shift Transition:** venturing into the unfamiliar territory of the
  microservice database approach is slowed down by the traditional monolitich
  database approach, originated when creating and managing a new instance was a
  complex task
- **Current CloudNativePG Limitations:** Particularly due to the absence of
  declarative management for resources within a database, such as foreign
  servers or certain extensions.

To address these situations, all you need to do is set `enableSuperuserAccess`
to `true`. The immediate effects are:

1. The appearance of a new secret named `cluster-example-superuser`.
2. Upon repeating the previous query on `pg_shadow`, only the
   `streaming_replica` user is returned.

The structure of the `cluster-example-superuser` secret closely mirrors that of
the `cluster-example-app`. For a detailed examination of the superuser secret
and the process of uncovering the actual password, refer back to the previous
recipe.

It's worth noting that superuser access can be enabled temporarily. If you
later set `enableSuperuserAccess` back to `false`, the system reverts to its
initial state—no secret, and the password remains set to `NULL`.

## The `ALTER SYSTEM` command

For those well-versed in PostgreSQL, the dynamic adjustment of settings is a
familiar concept achieved through the `ALTER SYSTEM` command.

However, exercising `ALTER SYSTEM` within a CloudNativePG managed cluster is
discouraged, and here's why:

- **Potential Operator Interference:** it might disrupt the operator's role in
  managing the **CLUSTER** (not just a single instance!).
- **Infrastructure as Code Concerns:** it poses a risk of breaking
  GitOps, change management policies and broader Infrastructure as Code
  practices.

The first concern is particularly crucial. Unlike PostgreSQL, which lacks a
built-in understanding of High Availability (HA) Clusters, Kubernetes demands a
self-healing approach. Consequently, we must conceptualize our setup as a
cluster composed of a primary instance and an arbitrary number of replicas,
instead of confining ourselves to a single instance. That's what CloudNativePG
is about.

This default safeguard is reflected in the inhibition of `ALTER SYSTEM` within
all PostgreSQL clusters created by CloudNativePG. Demonstrated below:

```sh
kubectl exec -ti -c postgres cluster-example-1 \
  -- psql -c 'ALTER SYSTEM SET archive_mode TO off'
```

Resulting in:

```console
ERROR:  could not open file "postgresql.auto.conf": Permission denied
command terminated with exit code 1
```

_(Note: there's actually a
[patch](https://www.postgresql.org/message-id/CA%2BVUV5rEKt2%2BCdC_KUaPoihMu%2Bi5ChT4WVNTr4CD5-xXZUfuQw%40mail.gmail.com)
I have proposed to disable this directly in PostgreSQL to improve the
usability)_

However, if the need arises, you can enable it by configuring
`.spec.postgresql.enableAlterSystem` to `true`.

## Conclusions

In conclusion, the CloudNativePG recipe thoroughly examines the default
security practices embedded within the framework. The emphasis on securing the
`postgres` user and implementing the principle of least authority (PoLA)
underscores CloudNativePG's commitment to default configurations that
prioritize high-level security.

The inspection of the `enableSuperuserAccess` setting sheds light on its
default value of `false`, aligning seamlessly with the PoLA philosophy. This
default configuration serves as a protective measure, restricting network
access for the `postgres` user—a crucial element employed by the operator for
seamless server coordination through the instance manager.

The exploration of PostgreSQL Host-Based Authentication configuration provides
valuable insights, highlighting the prevalence of the `peer` authentication
method and the default rule facilitating broad database connections through TLS
and non-TLS connections. The deliberate choice of a `NULL` password for the
`postgres` user adds an extra layer of security.

In essence, CloudNativePG steadfastly upholds a default stance that prioritizes
security and simplicity. Advanced users, however, are granted the flexibility
to fine-tune configurations such as `enableSuperuserAccess`. This nuanced
approach allows users to strike a delicate balance between stringent security
measures and operational necessities within PostgreSQL clusters.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!
