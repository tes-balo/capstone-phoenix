# Cost Analysis

## Monthly Infrastructure Cost

### Actual Monthly Infrastructure Cost (July 2026)


The Kubernetes cluster is deployed on Microsoft Azure using three Ubuntu Linux virtual machines. The infrastructure was intentionally designed to balance production-like architecture with affordability by using burstable B-series virtual machines.


Based on Azure Portal Cost Analysis:

| Resource | Quantity | Monthly Cost |
| --- | --- | --- |
| Standard_B2s_v2 (Control Plane) | 1 | $63.07 |
| Standard_B2ls_v2 (Worker Nodes) | 2 | $65.08 |
| Static Public IP Addresses | 3 | $10.50 |
| Storage Account (Remote State) | 1 | ~$1.00 |
| Managed Disks (OS) | 3 | ~$3.60 |
| Data Transfer | - | ~$2.00 |

**Total: ~$145/month**
> **Note:** Costs are estimates based on Azure Pay-As-You-Go pricing for the Sweden Central region and assume the virtual machines run continuously for an entire month (approximately 730 hours). Actual charges may vary depending on usage, pricing updates, and outbound network traffic.

---

# Resource Breakdown

## Control Plane

The Kubernetes control plane runs on a **Standard_B2s_v2** virtual machine.

Responsibilities include:

* Kubernetes API Server
* etcd datastore (embedded in k3s)
* Scheduler
* Controller Manager
* Traefik Ingress Controller
* Argo CD
* cert-manager
* Sealed Secrets Controller

A larger VM was selected for the control plane because it hosts the cluster management components in addition to several platform services.

---

## Worker Nodes

The application workloads are distributed across two **Standard_B2ls_v2** virtual machines.

These nodes host:

* Frontend Pods
* Backend Pods
* PostgreSQL StatefulSet
* Kubernetes system workloads

Using smaller worker nodes reduces infrastructure costs while still providing enough resources for the project workload.

---

## Storage

Each virtual machine uses a Standard SSD managed disk for the operating system.

Persistent application data is stored using a Persistent Volume Claim attached to the PostgreSQL StatefulSet, ensuring that database data survives pod recreation.

---

## Networking

The deployment includes:

* Azure Virtual Network
* Dedicated subnet
* Network Security Group
* Three static public IP addresses

Virtual Networks and Network Security Groups incur no direct charges, while Public IP addresses have a small monthly cost.

---

# Cost Optimisation Opportunities

Several optimisations could significantly reduce the monthly infrastructure cost without affecting the learning objectives of the project.

### Use Spot Virtual Machines

Replacing the worker nodes with Azure Spot VMs would reduce compute costs substantially for non-production environments.

---

### Shut Down the Cluster When Not in Use

Since this cluster is primarily for demonstration and learning, stopping the virtual machines outside development hours could reduce monthly costs considerably.

---

### Reduce Public IP Addresses

Only the control plane requires a public endpoint for administration and ingress. The worker nodes could operate entirely on private IP addresses, eliminating the cost of two Public IP resources.

---

### Managed DNS Consolidation

If additional projects share the same domain, DNS hosting costs can be consolidated across multiple deployments.

---

### Autoscaling

Introducing a Cluster Autoscaler would allow worker nodes to scale based on demand, reducing costs during periods of low utilisation.

---

# Estimated Cost After Optimisation

Applying the above optimisations could reduce the monthly operating cost to approximately **$40–50 USD**, primarily through:

* Removing unnecessary Public IP addresses.
* Powering off development VMs when idle.
* Using Spot VMs for worker nodes.

---

# Conclusion

The infrastructure was intentionally designed to balance production practices with cost efficiency. By combining lightweight k3s, burstable Azure B-series virtual machines, Infrastructure as Code, and GitOps, the platform delivers a realistic Kubernetes deployment while keeping operational costs relatively low for a learning environment. The architecture can also be scaled further or optimized depending on production requirements and budget constraints.
