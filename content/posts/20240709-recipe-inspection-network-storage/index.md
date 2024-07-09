---
title: "CloudNativePG Recipe 9 - Inspecting the network and the storage in a CloudNativePG cluster"
date: 2024-07-09T13:20:01+02:00
description: "Learn how to inspect networking and storage in a PostgreSQL cluster managed by CloudNativePG inside Kubernetes"
tags: ["PostgreSQL", "postgres", "kubernetes", "k8s", "cloudnativepg", "postgresql", "postgres", "DoK", "data on kubernetes", "CNPG", "high availability", "IaC", "Storage", "PersistentVolumeClaim", "ClusterIP", "Services", "Failover", "Labels", "Endpoints", "DBA"]
cover: cover.jpg
thumb: thumb.jpg
draft: false
---

_In this blog post, I delve into the crucial aspects of networking and storage
within a CloudNativePG cluster deployed on Kubernetes. I explore how Kubernetes
services manage external and internal communications for PostgreSQL clusters,
ensuring high availability and seamless failover. Additionally, I examine the
role of PersistentVolumeClaims in handling PostgreSQL data storage, offering
insights into effective resource management. This article provides an example
of the kind of knowledge DBAs need to acquire when managing PostgreSQL in
cloud-native environments, highlighting the importance of collaboration with
infrastructure teams and developers to ensure robust and resilient cluster
operations._

<!--more-->

---

In this article, I will cover two key resources essential for a CloudNativePG
cluster deployed in Kubernetes: **networking** and **storage**.

Networking is crucial for external communication between a PostgreSQL cluster
and applications, as well as for internal communication between PostgreSQL
instances for high availability (HA). Storage is a fundamental requirement for
any database, ensuring data persistence and reliability.

These concepts are also vital for database administrators (DBAs) transitioning
to Kubernetes. Networking surrounds our PostgreSQL cluster, while storage lies
beneath it. Understanding these aspects enables DBAs to collaborate effectively
with infrastructure and platform engineers, as well as developers, particularly
when managing `Cluster` resources.

---

**IMPORTANT:** This article requires the local playground covered in
[CNPG Recipe #1]({{< relref "../20240303-recipe-local-setup/index.md">}}).
For a broader understanding, I recommend also going through
[Recipes #2]({{< relref "../20240307-recipe-inspection/index.md">}})
and [#3]({{< relref "../20240312-recipe-superuser/index.md">}}).

---

Let’s connect to your local Kubernetes cluster in `kind` and check the list of
PostgreSQL clusters:

```sh
kubectl get clusters
```

Returning:

```console
NAME              AGE     INSTANCES   READY   STATUS                     PRIMARY
cluster-example   86s   3           3       Cluster in healthy state   cluster-example-1
```

The `cluster-example` cluster comprises three instances, a primary
(`cluster-example-1`) and two standby instances (`cluster-example-2` and
`cluster-example-3`). Each instance runs in a separate pod, as shown with the
following command:

```sh
kubectl get pods
```

Returning:

```console
NAME                READY   STATUS    RESTARTS   AGE
cluster-example-1   1/1     Running   0          81s
cluster-example-2   1/1     Running   0          61s
cluster-example-3   1/1     Running   0          43s
```

CloudNativePG is responsible for the PostgreSQL cluster resource and leverages
the Kubernetes API for both networking (using the `Service` resource) and
storage (via the `PersistentVolumeClaim` and, indirectly, `StorageClass`
resources) without reinventing the wheel. Kubernetes coordinates all these
components, trusting the CloudNativePG controller to manage these resources and
converge the observed state of a Postgres cluster to the desired one. This
makes an operator special when managing a database workload like Postgres.

Let’s now start with the networking side.

# Networking

[Kubernetes provides a standard resource called `Service`](https://kubernetes.io/docs/concepts/services-networking/service/),
an abstraction that enables exposing a group of pods over a network. In the
context of CloudNativePG, this service exposes the PostgreSQL TCP service (port
5432) of each instance running in a pod, allowing applications to connect
seamlessly.

The first question that comes to mind is: _"How can I connect to the primary?”_

CloudNativePG abstracts the complexity of PostgreSQL's primary/standby
architecture by providing a service that always points to the primary instance.
This eliminates the need for applications to know the specific pod name where
the primary runs. Each cluster includes a mandatory `Service` object, named
after the cluster with the `-rw` suffix, of type `ClusterIP`, which points to
the IP of the pod running the primary.

The second question that comes to mind is: _"What happens if the primary goes down?"_

CloudNativePG's controller ensures that in the event of a primary failure, the
service promptly points to the new primary by using its selector, which relies
on pod labels to identify the target. CloudNativePG correctly sets these labels
on the pods (and on storage, as we’ll discuss later) to first remove the link
to the former primary and then, after promotion, point to the new leader. This
automated failover mechanism provides high availability and self-healing
capabilities. This approach treats PostgreSQL databases more like cattle than
pets, although I advocate for a middle ground where PostgreSQL instances are
treated more specially than cattle but not quite as uniquely as pets—hence my
motto: cattle vs. pets (vs. elephants).

Additionally, the service ensures the correct routing during routine
maintenance tasks such as updates, configuration changes, and switchovers.

Furthermore, CloudNativePG automatically creates a `-ro` service, which points
to any available hot standby instances (replicas accepting read-only
transactions) for read-only queries, and a `-r` service, which points to any
available instance. Version 1.24 introduces support for the
`.spec.managed.services.disabledDefaultServices` option, allowing us to skip
the generation of these two default services.

By managing these services, the operator provides a robust and resilient
PostgreSQL environment that adheres to Cloud Native principles. This allows
developers to focus on building and maintaining their applications without
worrying about the underlying database infrastructure.

To view the services managed by the operator, use the following command:

```sh
kubectl get services
```

This command will list all the Kubernetes services associated with your
CloudNativePG cluster, giving you an overview of the available resources:

```console
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
cluster-example-r    ClusterIP   10.96.69.243    <none>        5432/TCP   93s
cluster-example-ro   ClusterIP   10.96.194.161   <none>        5432/TCP   93s
cluster-example-rw   ClusterIP   10.96.239.81    <none>        5432/TCP   93s
kubernetes           ClusterIP   10.96.0.1       <none>        443/TCP    5m
```

Let’s examine the `cluster-example-rw` service in more detail with:

```sh
kubectl describe service cluster-example-rw
```

Returning:

```console
Name:              cluster-example-rw
Namespace:         default
Labels:            cnpg.io/cluster=cluster-example
Annotations:       cnpg.io/operatorVersion: 1.23.2
Selector:          cnpg.io/cluster=cluster-example,role=primary
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.96.239.81
IPs:               10.96.239.81
Port:              postgres  5432/TCP
TargetPort:        5432/TCP
Endpoints:         10.244.0.20:5432
Session Affinity:  None
Events:            <none>
```

Pay attention to the `Selector` field, which identifies the primary pod of the
`cluster-example` cluster. Ultimately though, the most relevant information is in the
`Endpoints` section, which shows a single entry: TCP port 5432 on host
10.244.0.20. Let’s retrieve the IPs of our pods:

```sh
kubectl get pods -o wide
```

Returning:

```console
NAME                READY   STATUS    RESTARTS   AGE     IP            NODE                 NOMINATED NODE   READINESS GATES
cluster-example-1   1/1     Running   0          7m52s   10.244.0.20   cnpg-control-plane   <none>           <none>
cluster-example-2   1/1     Running   0          7m32s   10.244.0.23   cnpg-control-plane   <none>           <none>
cluster-example-3   1/1     Running   0          7m14s   10.244.0.26   cnpg-control-plane   <none>           <none>
```

As you can see, `10.244.0.20` is the IP address of the `cluster-example-1` pod,
which runs the primary PostgreSQL instance.

If you describe the `cluster-example-ro` service, you will see two endpoints:
`10.244.0.23:5432` and `10.244.0.26:5432`.

This automation leverages the concept of Kubernetes' service selectors in
Kubernetes, eliminating the need to manually coordinate changes with Virtual
IPs, DNS entries, and connection poolers. It significantly simplifies
management and reduces the risk of errors, including split-brain scenarios
where different cluster instances mistakenly assume they are the primary.

Another useful command is:

```sh
kubectl get endpoints
```

Returning all the endpoints:

```console
NAME                 ENDPOINTS                                            AGE
cluster-example-r    10.244.0.20:5432,10.244.0.23:5432,10.244.0.26:5432   10m
cluster-example-ro   10.244.0.23:5432,10.244.0.26:5432                    10m
cluster-example-rw   10.244.0.20:5432                                     10m
kubernetes           172.18.0.2:6443                                      15m
```

# Storage

CloudNativePG directly manages PostgreSQL files. In the simplest scenario, it
handles a single volume containing the `PGDATA` directory, where all PostgreSQL
data files are stored. Additionally, you can separate Write-Ahead Log (WAL)
files into a different volume and manage PostgreSQL tablespaces as separate
volumes.

PostgreSQL volumes are instantiated through a
[standard Kubernetes resource called `PersistentVolumeClaim` (PVC)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/),
which defines the request for persistent storage for a pod. Let’s list the PVCs
in our example:

```sh
kubectl get pvc
```

Returning:

```console
NAME                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
cluster-example-1   Bound    pvc-5ecd8058-84a5-456b-8498-24ea5283c9bd   1Gi        RWO            standard       11m
cluster-example-2   Bound    pvc-485f6e81-63c4-428f-ac34-3f6b557665a7   1Gi        RWO            standard       11m
cluster-example-3   Bound    pvc-6a94ce46-43e2-4741-bd19-e117019f16f5   1Gi        RWO            standard       11m
```

Next, let’s get more information about the PVC of the first pod by running:

```sh
kubectl describe pvc cluster-example-1
```

We should expect an output similar to the following:

```console
Name:          cluster-example-1
Namespace:     default
StorageClass:  standard
Status:        Bound
Volume:        pvc-5ecd8058-84a5-456b-8498-24ea5283c9bd
Labels:        cnpg.io/cluster=cluster-example
               cnpg.io/instanceName=cluster-example-1
               cnpg.io/instanceRole=primary
               cnpg.io/pvcRole=PG_DATA
               role=primary
Annotations:   cnpg.io/nodeSerial: 1
               cnpg.io/operatorVersion: 1.23.2
               cnpg.io/pvcStatus: ready
               pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-provisioner: rancher.io/local-path
               volume.kubernetes.io/selected-node: cnpg-control-plane
               volume.kubernetes.io/storage-provisioner: rancher.io/local-path
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      1Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       cluster-example-1
Events:        <none>
```

Key information includes:

- **Storage Class**: The default storage class (`standard` in our environment)
  is used because none was specified in the `.spec.storage` stanza. You can
  check this by running:

    ```sh
    kubectl get storageclass
    ```

    Returning:

    ```console
    NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  16m
    ```

- **Volume:** The name of the persistent volume associated with the PVC and
  subsequently with the `cluster-example-1` pod (see `Used By`).

- **Labels and Annotations**: Starting with `cnpg.io`, these are controlled and
  managed by CloudNativePG (e.g., `cnpg.io/pvcRole=PG_DATA` indicates that the
  volume contains the `PGDATA`).

- **Volume Mode**: Set to `Filesystem`, meaning the volume is mounted as a
  directory in the file system of the pod.

- **Access Mode**: Set to `ReadWriteOnce` (RWO).

- **Capacity**: The size of the volume.

If you are curious, you can get more information about the underlying storage
class or the persistent volumes using the `kubectl describe storageclass standard`
and `kubectl describe pv cluster-example-1` commands.

# Conclusions

To summarise, a PostgreSQL `Cluster` resource sits between applications and the
storage, with networking seamlessly enabling secure connections with the
database. CloudNativePG uses standard Kubernetes resources, facilitating
conversations between infrastructure teams and DBAs/developers who are
responsible for a PostgreSQL cluster.

DBAs operating in a multidisciplinary development team don’t need to master the
entire Kubernetes ecosystem.  They only need to learn enough Kubernetes to
manage PostgreSQL `Cluster` objects effectively, thus enabling them to
participate in intelligent conversations with their counterparts — from
planning the architecture and storage (day 0) to managing production
environments (day 2).

In this article, I covered networking, including the read-only service that
enables distributing reads on a replica through
[PostgreSQL hot standby capability](https://www.postgresql.org/docs/current/hot-standby.html),
and storage, focusing on persistent volume claims. Take time to familiarise
yourself with these resources, conduct your research, and experiment. This will
enhance your knowledge and improve the overall performance of PostgreSQL in
Kubernetes.

---

Stay tuned for the upcoming recipes! For the latest updates, consider
subscribing to my [LinkedIn](https://www.linkedin.com/in/gbartolini/) and
[Twitter](https://twitter.com/_GBartolini_) channels.

If you found this article informative, feel free to share it within your
network on social media using the provided links below. Your support is
immensely appreciated!

_Cover Picture: [Royalty-Free photo: elephant, african bush elephant, wilderness, national park, safari, animal, africa, watering hole, mirroring, drink, mammals](https://www.pickpik.com/elephant-african-bush-elephant-wilderness-national-park-safari-animal-40974)._
