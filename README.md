
# Experiment solutions for Kubernetes Multi-Tenancy

This is a collection of bash scripts that I used to test some hard multi-tenancy solutions for a Kubernetes cluster.

## Prerequisites
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- A Kubernetes cluster already configured in your `kubectl` context with a CNI plugin already installed.

## Scripts
- Install utilities:
  - [setup.sh](examples/quick-start/setup.sh): Install all the necessary tools to run the scripts and the components for the multi-tenancy tests.
- Create a tenant:
  - [new-vcluster.sh](examples/create-tenant/new-vcluster.sh): Create a new vCluster for a tenant.
  - [new-kv-cluster.sh](examples/create-tenant/new-kv-cluster.sh): Create a new Kubevirt cluster for a tenant.
  - [get-kubeconfig.sh](examples/create-tenant/get-kubeconfig.sh): Get the kubeconfigs for the tenant clusters.
- Get relevant metrics:
  - [pod-boot-time.sh](examples/metrics/pod-boot-time.sh): Get the time used for a pod to be ready (can be used to get the boot time of a tenant cluster for vCluster).
  - [kvcluster-boot-time.sh](examples/metrics/kvcluster-boot-time.sh): Get the tenant Kubevirt cluster boot time.

## Multi-Tenancy solutions
This section describes the solutions and why I picked them for my tests.
### Management plane 
The management of multiple cluster is handled with [Cluster API](https://github.com/kubernetes-sigs/cluster-api) and the tenant clusters are created with [vCluster](https://github.com/loft-sh/cluster-api-provider-vcluster) and [Kubevirt](https://github.com/kubernetes-sigs/cluster-api-provider-kubevirt) providers. This seems to be a good solution for multi-tenancy, as it allows creating and managing multiple clusters with a single API that respects the loved declarative Kubernetes API.
### Control and data plane
As described in the [Kubernetes documentation](https://kubernetes.io/docs/concepts/security/multi-tenancy/), the multi-tenancy can be achieved with different strategies, according to how you isolate the control and data plane of the cluster. Each choice has its own trade-offs:
- **Control plane**: Ensures that different tenants cannot access or affect each others Kubernetes API resources.
  - **Shared control plane**: All tenants share the same control plane. This is the default Kubernetes behavior and is the simplest to manage, but it is not secure as a tenant can access the API resources of another tenant.
    - **Namespace based solutions**: Each tenant has its own namespace. RBAC can be used to restrict access to the resources of a namespace. Not ideal for hard multi-tenancy because of the risk of role escalation.
  - **Dedicated control plane**: Each tenant has its own control plane. This is the most secure solution, but it is also the most complex to manage and the most expensive to run (lots of redundant resources).
- **Data plane**: Ensures that different tenants cannot access or influence each other's workloads.
  - **Shared data plane**: All tenants share the physical data plane. Each tenant uses its own virtual data plane, but actually concurs on the same physical resources. This is the simplest to manage and the most cost-effective solution, but each resource must be isolated and the risk of noisy neighbors is high.
  - **Dedicated data plane (node isolation)**: Each tenant has its own nodes with exclusive access to the physical resources. This is not so typical and can have serious security implications for the infrastructure.

## Picked solutions

### Cluster nodes as VMs
The most common solution for hard multi-tenancy is to dedicate a control plane for each tenant and isolate the shared data plane with VMs. Each tenant cluster's node is a VM and will naturally be isolated from the other tenants. The infrastructure is shared, but the tenants are isolated and the infrastructure owner can assign resources by attaching them to the VMs. This is the solution that I picked for my tests by using **Kubevirt** to create VMs for the tenant clusters.

Even though KubeVirt is the most used solution for running VMs in Kubernetes, it is not the only one nor the most efficient. An alternative solution is [VirtInk](https://github.com/smartxworks/virtink) that uses Cloud-Hypervisor as VMM instead of QEMU. This solution is more efficient and can be used to run VMs in a Kubernetes cluster with a lower overhead.

### Cluster in sandboxed pods
Another solution can be to install a dedicated control plane (k8s/k3d/k0s distribution) inside a pod for each tenant. The tenant can access the Kubernetes API of its own control plane and won't affect other (isolating tenants control planes as a result). A new cluster can be created just by deploying new pods. This is the solution that I picked for my tests by using **vCluster**.

The data plane isolation must be address differently. In the previous solution, both control and data plane isolation could be achieved in one step, by placing everything in a VM. However, VM-based solutions are still the most efficient way to isolate workloads, so the most common solution still is to use VMs for the data plane with **pod sandboxing**. The VMs isolated directly pods (not the nodes) transparently by using a Container Runtime Interface (CRI) shim that for each pod it actually creates a VM and then place inside the pod. You don't need full-bloated and resource demanding VMs to run a pod workload, so microVMs (“lightweight” VMs) are used instead. **Kata Runtime** is the most used solution for this task.

This is why I used both **vCluster** and **Kata Runtime** as a solution for my tests. It may be harder to configure, but it may be more efficient and secure than provisioning a set of full VMs for each tenant with a Kubernetes cluster inside.
