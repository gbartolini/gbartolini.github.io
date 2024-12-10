---
title: "CloudNativePG Recipe #15 - Effectively read your PostgreSQL logs"
date: # Run `date -Iseconds | pbcopy"
description: ""
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "cnpg", "postgresql", "postgres", "dok", "data on kubernetes", "logs"]
cover: cover.jpg
thumb: thumb.jpg
draft: true
---

_ABSTRACT_

<!--more-->

---

CloudNativePG is designed to handle PostgreSQL logs in a way that aligns seamlessly with Kubernetes practices. Each container managed by CloudNativePG streams its logs in JSON format directly to the standard output channel. This approach aligns with Kubernetes administrators who rely on the `kubectl logs` command, but often surprises PostgreSQL DBAs, who are accustomed to searching for logs stored within the database container.

However, in CloudNativePG, PostgreSQL logs are **not stored inside the container**, enhancing the security posture of the infrastructure by default.  

To understand the rationale behind this design, it’s important to revisit the scope of CloudNativePG: integrating PostgreSQL clusters into a Kubernetes-managed environment where PostgreSQL is treated as an application—albeit a critical one (["cattle vs pets? no, elephant herds!"](https://www.cncf.io/blog/2024/11/20/cloud-neutral-postgres-databases-with-kubernetes-and-cloudnativepg/)).

In such an ecosystem, effective observability depends on centralized log management solutions rather than individual applications managing their own logs. These systems aggregate, store, and control access to logs with fine-grained permissions, ensuring secure and efficient handling.  For example, PostgreSQL audit logs should only be accessible to a restricted group of individuals.

This centralized approach ensures better security, compliance, and scalability, while also aligning with modern Kubernetes-native operational practices.

Having said this, it is important to provide ways to quickly access logs from the command line interface. In the [previous article](https://www.gabrielebartolini.it/articles/2024/10/cnpg-recipe-14-useful-command-line-tools/#stern-for-log-inspection) I briefly covered `stern`.

Here I want to highlight the capabilities provided by the `logs` command of the `cnpg` plugin for `kubectl`.




<!--
# ["CloudNativePG Recipe 1 - Setting up your local playground in minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}})

```yaml
{{< include "yaml/cluster-example.yaml" >}}
```
-->

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

