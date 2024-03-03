---
title: "CloudNativePG Recipe x - Simulating a multi-node Kubernetes cluster with kind"
date: 2024-03-03
description: ""
tags: ["postgresql", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "dok", "data on kubernetes", "kind", "docker", "operator", "cluster", "cnpg", "ci/cd pipelines", "e2e testing", "developer productivity", "deployment automation", "cloudnative databases"]
cover: cover.png
thumb: thumb.png
draft: true
---

_ABSTRACT_

<!--more-->

---

Start from ["CloudNativePG Recipe 1 - Setting up your local playground in minutes"]({{< relref "../20240303-recipe-local-setup/index.md" >}})

See [multi-node.yaml](yaml/multi-node.yaml)

```sh
kubectl get nodes -L workload
```
