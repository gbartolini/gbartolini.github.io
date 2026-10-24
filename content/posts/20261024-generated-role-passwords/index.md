---
title: "CNPG Recipe 28 - Generated and rotating PostgreSQL user passwords in CloudNativePG 1.31"
date: 2026-10-24T18:34:09+02:00
description: "CloudNativePG 1.31 lets a DatabaseRole generate its own PostgreSQL password, shape it with criteria and rotate it monthly, with no Secret to prepare."
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "dok", "data on kubernetes", "databaserole", "roles", "passwords", "password-rotation", "secrets", "security", "external-secrets", "declarative-configuration", "operator", "tutorial", "guide"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_A first look at what CloudNativePG 1.31 will bring to PostgreSQL credentials:
a `DatabaseRole` can now generate its own password, keep it in a Secret the
operator owns, shape it with criteria and rotate it on a schedule, with
PostgreSQL enforcing the lifetime through `VALID UNTIL`. The feature is merged
but not yet released, so this recipe anticipates 1.31 and shows how to try it
today on the latest development snapshot._

<!--more-->

---

When CloudNativePG 1.30 introduced the `DatabaseRole` resource, I wrote about
[declarative roles and passwordless TLS]({{< relref "../20260706-databaserole-tls-client-certificates/index.md" >}})
and left one uncomfortable detail for later: if a PostgreSQL role needed a
password, you still had to create the Secret holding it beforehand. The
operator would apply the password, but where it came from, and how long it
stayed the same, was entirely your problem.

That gap closed yesterday, when the
[pull request](https://github.com/cloudnative-pg/cloudnative-pg/pull/11337)
that lets the operator generate the password of a `DatabaseRole` was merged. It
will be part of CloudNativePG 1.31, due in the last quarter of the year, and
it is not in any released version yet.

The feature was requested by some of our customers at EDB, and we were happy
to contribute it to the CloudNativePG open source project, where it closes the
long-standing issue
[#3788](https://github.com/cloudnative-pg/cloudnative-pg/issues/3788).

## Trying it today

To test it you need the latest development snapshot of the operator, built
from the current trunk. The documentation describes how to install it from the
[cloudnative-pg/artifacts](https://github.com/cloudnative-pg/artifacts)
repository:

```sh
curl -sSfL \
  https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
  kubectl apply --server-side -f -
```

{{< alert >}}
Snapshots are not for production, so use a throwaway cluster, for instance
on kind. Everything below is based on the merged code and its documentation,
and the behaviour may still change before the release.
{{< /alert >}}

{{< alert "circle-info" >}}
The documentation for the feature is already published, in the
[role management page](https://cloudnative-pg.io/docs/devel/declarative_role_management)
of the development version. Every documentation link in this recipe points
there, rather than to the usual `current` version, because `current` only
reflects the latest release and 1.31 is not out yet. Once it is, those pages
will be available under `current` too.
{{< /alert >}}

## The password stanza

A `DatabaseRole` now has a `password` stanza with a required `mode` field.
Four modes cover the whole life of a credential, in place of the combination
of `passwordSecret` and `disablePassword` that I never found particularly
readable:

- `generate`: the operator creates the password and keeps it in a Secret it
  owns.
- `secret`: the operator reads the password from a Secret you supply and
  never writes to it.
- `external`: the operator leaves the password alone, because something else
  manages it.
- `setNull`: the operator sets the password to `NULL`, disabling password
  authentication for the role.

This recipe is about `generate`. The `secret` and `setNull` modes are the
explicit equivalents of `passwordSecret` and `disablePassword`, which remain
available but are deprecated and cannot be combined with the stanza. There is
no default for `mode` on purpose: asking for a password without saying how it
is managed is ambiguous, and a wrong guess either creates a credential or
removes one.

## A generated password, step by step

Start with the smallest possible cluster:

```yaml
{{< include "yaml/cluster.yaml" >}}
```

Then declare a role that logs in and lets the operator take care of its
password, rotating it roughly once a month:

```yaml
{{< include "yaml/angus.yaml" >}}
```

The `duration` of 720 hours gives each password a lifetime of 30 days, and
`renewBefore` asks the operator to replace it a day ahead of the expiration.
In practice the password changes every 29 days. That is the cadence I would
start with for most workloads: frequent enough that a leaked credential has a
bounded lifetime, rare enough that nobody gets paged because of it.

The operator creates a Secret of type `kubernetes.io/basic-auth`, named after
the `DatabaseRole` with a `-password` suffix, so `angus-password` here. The
suffix guarantees uniqueness within the namespace, and you can pick a
different name with `password.secret`. The Secret carries three keys:

- `username`: the PostgreSQL role name.
- `password`: the generated password.
- `pgpass`: a ready-made `.pgpass` line for the role.

The first two are what the instance manager applies to PostgreSQL. The third
is a convenience for whoever consumes the credential. It wildcards host and
database, since the credential belongs to the role and not to an endpoint:

```console
$ kubectl get secret angus-password -o jsonpath='{.data.pgpass}' | base64 -d
*:5432:*:angus:<the generated password>
```

Appending that line to `~/.pgpass` is enough for libpq to authenticate
without the password ever appearing in a connection string or in your shell
history. The Secret also has an owner reference to the `DatabaseRole`, so
deleting the role garbage-collects the Secret, whatever the reclaim policy
says about the PostgreSQL role itself.

On the database side, the password is stored as a SCRAM-SHA-256 verifier, as
you would expect, and the role gets a `VALID UNTIL` timestamp that follows
the expiration of the generated password:

```console
$ kubectl cnpg psql acdc
psql (18.6 (Debian 18.6-1.pgdg13+2))
Type "help" for help.

postgres=# SELECT rolname, rolcanlogin, rolvaliduntil
           FROM pg_authid WHERE rolname = 'angus';
 rolname | rolcanlogin |     rolvaliduntil
---------+-------------+------------------------
 angus   | t           | 2026-11-23 09:13:23+00
(1 row)
```

The lifetime is not just a promise the operator makes: PostgreSQL itself
refuses the password for new connections once it has expired, so a rotation
that fails to happen results in a closed door rather than in a credential that
quietly lives forever.

## Observing and triggering rotation

The state of the password is recorded in the `status` of the `DatabaseRole`.
This is what `kubectl get -o yaml databaseroles.postgresql.cnpg.io angus`
returns for the monthly role above (trimmed to the `status` section):

```yaml
status:
  applied: true
  conditions:
  - lastTransitionTime: "2026-10-24T09:13:23Z"
    message: "2178"
    reason: ChangeDetected
    status: "True"
    type: PasswordSecretChange
  observedGeneration: 2
  password:
    appliedExpiration: "2026-11-23T09:13:23Z"
    expiration: "2026-11-23T09:13:23Z"
    issuedAt: "2026-10-24T09:13:23Z"
    secretName: angus-password
  secretResourceVersion: "2178"
```

`issuedAt` is the only load-bearing field: the operator recomputes
`expiration` from it and from the current `duration` and `renewBefore` at
every reconciliation, so changing either takes effect immediately.
`appliedExpiration` tells you when the change reached the database, which is
what you want to check if you suspect a rotation did not complete. The
expiration is also a column of `kubectl get databaserole`, and the events
record the generation and every later rotation:

```console
$ kubectl get databaseroles.postgresql.cnpg.io
NAME    AGE     CLUSTER   PG NAME   APPLIED   MESSAGE   PASSWORD EXPIRATION    CERTIFICATE EXPIRATION
angus   4m12s   acdc      angus     true                2026-11-23T09:13:23Z

$ kubectl describe databaserole angus
...
Events:
  Type    Reason             Age    From                         Message
  ----    ------             ----   ----                         -------
  Normal  PasswordGenerated  4m48s  cloudnative-pg-databaserole  Generated the password of role "angus" into Secret "angus-password"
```

After the first rotation, a `PasswordRotated` event appears next to it.

If you cannot wait for the schedule, for instance after a suspected leak,
annotate the role to rotate immediately, with any value:

```sh
kubectl annotate databaserole angus cnpg.io/rotatePassword=now
```

The annotation is a one-shot request: the operator removes it once the
rotation has happened, and the `PasswordRotated` or `PasswordRotationIgnored`
event tells you whether the request was honoured.

## Shaping the password

By default the operator generates 24 characters, with digits and mixed case
and no symbols. Symbols are excluded deliberately: passwords end up in
connection strings, URIs and `.pgpass` files, where many punctuation
characters need escaping. When a policy requires them, the `criteria` block,
modelled on the External Secrets Operator's password generator, gives you
control, as in this version of the same role (`noUpper` and `allowRepeat` are
shown with their default values):

```yaml
{{< include "yaml/angus-criteria.yaml" >}}
```

Characters do not repeat unless `allowRepeat` is set, so some combinations
cannot be satisfied: more than 52 letters, more than ten digits or more
symbols than `symbolCharacters` contains. The API rejects those when you
apply the manifest. A combination that only the generator can rule out is
reported in `status.password.message`, and the operator waits for you to fix
the specification instead of retrying forever.

## Why rotation is off by default

`duration` is optional. Without it, the password is generated once and never
changes: the documentation recommends setting one, but the operator does not
impose it. The reason is that a PostgreSQL role has exactly one password.
Unlike a certificate renewal, there is no overlap, and once `ALTER ROLE` runs
the old password stops working for new connections.

The impact is smaller than it sounds, because PostgreSQL evaluates the
password at connection time only. Open sessions keep working, and an
application that reconnects simply reads the new password again. Care is
needed only for applications that cache the password for the life of the
process: they fail at their next reconnection, after a failover or a network
blip. Enable `duration` for consumers that re-read the Secret when they
reconnect, and expect a short window in which the Secret already carries a
password the database has not applied yet.

## Behaviour worth knowing

A few rules are worth remembering:

- The operator never overwrites or deletes a Secret it does not own. If a
  Secret with the chosen name already exists, the conflict appears in
  `status.password.message` and nothing is generated until you resolve it.
- On a replica cluster no password is generated, because the role and its
  password belong to the primary cluster and are replicated from it.
  Generation starts after promotion.
- Changing `password.secret` generates a new password into the new Secret and
  deletes the previous one.
- Moving from `generate` to `external` or `setNull` deletes the generated
  Secret and sets the password to `NULL` once, so that no credential is left
  behind that nobody can read.
- Moving from `generate` to `secret` also deletes the generated Secret, even
  if `password.secret` names it, because the operator deletes what it created.
  Copy the password into a Secret of your own before switching.

The last two points matter for GitOps workflows, where a mode change is
simply a diff in a pull request. The [reference
documentation](https://cloudnative-pg.io/docs/devel/declarative_role_management#mode-generate)
has the full transition table.

## Generate, or let someone else generate

Does this make the External Secrets Operator (ESO) redundant? Not at all, and
I tested the integration too. If your organisation already keeps credentials in a vault
and distributes them with ESO, `mode: secret` pointing at the Secret that ESO
produces remains the right choice, and the documentation now includes a
[worked example](https://cloudnative-pg.io/docs/devel/cncf-projects/external-secrets#managing-the-password-of-a-databaserole)
with ESO's password generator. `mode: generate` is for the many cases where
nothing external is needed: the credential is born, lives and dies with the
role, and no extra component has to be installed and kept healthy for that to
work.

## Conclusion

With generated passwords, a `DatabaseRole` becomes a complete declaration of
an identity: its attributes, its authentication (a password, a client
certificate or both) and the lifecycle of its credentials. Rotation is a field, not a
cron job, and the lifetime is enforced by PostgreSQL through `VALID UNTIL`
rather than by good intentions.

Another important feature is planned for 1.31 as well: configurable `duration`
and `renewBefore` for the TLS client certificates of a `DatabaseRole` (which I
covered in
[Recipe 25]({{< relref "../20260706-databaserole-tls-client-certificates/index.md" >}})),
so that certificates get the same lifecycle controls as passwords. It is
tracked in
[issue #11312](https://github.com/cloudnative-pg/cloudnative-pg/issues/11312).

Since the feature is only just merged, feedback now is worth more than
feedback later. If you try the snapshot, tell us what works, what surprises
you and what is missing, either on the pull request or on the CloudNativePG
community's
[CNCF Slack](https://github.com/cloudnative-pg#getting-in-touch).

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_This article was drafted and refined with the assistance of Claude
(Anthropic). All technical content, corrections and editorial direction are
the author's own._

<!--
_Cover Picture: ["Elephant, path, Africa, Tanzania"](https://www.pickpik.com/elephant-path-africa-tanzania-animal-wildlife-133828)._
-->
