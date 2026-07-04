# Architecture

## 1. Topology Diagram

The following diagram illustrates the physical infrastructure, Kubernetes components, and application request flow.

![alt text](image.png)

The application is deployed across three Azure virtual machines. The control plane hosts the Kubernetes API server and Traefik Ingress Controller, while application workloads are distributed across the two worker nodes using Kubernetes topology spread constraints.

---

# 2. Node & Network

## Cluster Nodes

| Node          | Role                            | VM Size          | Private IP | Region         |
| ------------- | ------------------------------- | ---------------- | ---------- | -------------- |
| Control Plane | Kubernetes API Server + Traefik | Standard_B2s_v2  | 10.0.1.4   | Sweden Central |
| Worker 1      | Application Workloads           | Standard_B2ls_v2 | 10.0.1.5   | Sweden Central |
| Worker 2      | Application Workloads           | Standard_B2ls_v2 | 10.0.1.6   | Sweden Central |

All virtual machines run Ubuntu Server 22.04 LTS.

---

## Network Design

The infrastructure uses a dedicated Azure Virtual Network with the following addressing:

* Virtual Network: **10.0.0.0/16**
* Subnet: **10.0.1.0/24**

Using a private address space isolates cluster communication from the public internet while leaving sufficient room for future expansion.

Pods communicate over the Calico overlay network, while Kubernetes Services provide stable virtual IP addresses for service discovery.

---

## Firewall Configuration

The Azure Network Security Group follows the principle of least privilege.

Publicly accessible ports:

* TCP 22 (SSH) — restricted to my public IP only.
* TCP 80 (HTTP) — required for ACME HTTP-01 validation and HTTP traffic.
* TCP 443 (HTTPS) — public application access.

Internal-only traffic:

* Kubernetes node communication.
* Overlay networking.
* Pod-to-pod communication.
* Service networking.

The Kubernetes API Server (TCP 6443) is **not exposed to the public internet**. Access is restricted to my trusted IP address for administrative operations, significantly reducing the cluster's attack surface.

---

# 3. Request Flow

A client request begins with a DNS lookup through AWS Route 53, which resolves either **taskapp.tesbuilds.fun** or **api.tesbuilds.fun** to the public IP of the Kubernetes cluster. The request reaches the Traefik Ingress Controller over HTTPS on port **443**, where TLS is terminated using certificates automatically issued by cert-manager and Let's Encrypt. Based on the requested hostname, Traefik forwards traffic to the appropriate Kubernetes Service. Requests for **taskapp.tesbuilds.fun** are routed to the **frontend Service (ClusterIP:80)**, which load-balances traffic across the frontend pods. Requests made by the frontend to `/api` are forwarded to the **backend Service (ClusterIP:5000)**, which distributes traffic across backend replicas. The backend communicates with PostgreSQL through the **postgres headless Service (port 5432)** using Kubernetes DNS (`postgres.taskapp.svc.cluster.local`). Database reads and writes are then handled by the PostgreSQL StatefulSet using its Persistent Volume Claim, ensuring application data persists across pod restarts.

---

# 4. The Single-Server Assumptions I Fixed

| Single-server assumption                              | Why it breaks at scale                                                                                          | How I fixed it                                                                                                 |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Database migrations run in the application entrypoint | Multiple backend replicas may attempt to execute `alembic upgrade head` simultaneously, causing race conditions | Implemented a dedicated Kubernetes **Job** that performs migrations before backend replicas become available   |
| Database data stored in a local Docker volume         | Pods may be rescheduled to different nodes, causing local storage to be lost                                    | Deployed PostgreSQL as a **StatefulSet** with a **Persistent Volume Claim (PVC)**                              |
| Containers expose host ports directly                 | Multiple replicas across multiple nodes cannot all bind to the same host ports                                  | Used Kubernetes **Services** and **Traefik Ingress** to provide a single stable entry point                    |
| Manual application deployment using Docker Compose    | Manual deployments are error-prone and difficult to reproduce consistently                                      | Adopted **Argo CD GitOps**, making Git the single source of truth for deployments                              |
| Single application instance                           | Failure of the only application instance causes complete downtime                                               | Deployed frontend and backend as **Deployments** with multiple replicas                                        |
| Pods always restart on the same machine               | Kubernetes may schedule replacement pods on different worker nodes                                              | Used Kubernetes Deployments and StatefulSets, allowing workloads to recover automatically                      |
| Secrets stored in environment files                   | Plaintext secrets should not be committed to version control                                                    | Stored sensitive values as **Sealed Secrets**, allowing encrypted secrets to be safely committed to Git        |
| Health is assumed if the container starts             | Containers may become unhealthy after startup                                                                   | Configured **liveness** and **readiness probes** for all application workloads                                 |
| Rolling deployments briefly interrupt users           | Terminating all replicas simultaneously causes downtime                                                         | Configured **RollingUpdate** strategy with `maxUnavailable: 0` and `maxSurge: 1` for zero-downtime deployments |
| Multiple replicas may be scheduled onto the same node | Losing a single node could take down every replica                                                              | Added **topologySpreadConstraints** to distribute frontend and backend replicas across worker nodes            |

---

# 5. Choices & Trade-offs

## Raw YAML vs Helm vs Kustomize

Application workloads were deployed using **raw Kubernetes YAML manifests**. This approach provides complete visibility into every Kubernetes resource, making it easier to understand how each component functions and satisfying the educational objectives of the capstone. Helm was reserved for installing third-party infrastructure components such as cert-manager and Sealed Secrets because these projects publish and maintain official Helm charts.

---

## ingress-nginx vs Traefik

I chose the **Traefik Ingress Controller** because it is the default ingress controller bundled with k3s. This reduced installation complexity, integrates well with lightweight Kubernetes clusters, and works seamlessly with cert-manager for automatic TLS certificate provisioning. Using the built-in controller also reduced operational overhead compared to deploying an additional ingress solution.

---

## CNI / Network Policy Enforcement

The cluster uses **Calico** as its Container Network Interface (CNI). Calico was selected because it provides both pod networking and Kubernetes NetworkPolicy enforcement, capabilities not offered by the default Flannel networking used by k3s. During implementation, Calico was configured to use **VXLAN encapsulation** instead of IPIP because Azure drops native IPIP traffic between virtual machines.

---

## Secrets Management

Secrets are managed using **Bitnami Sealed Secrets**. Standard Kubernetes Secrets are only base64 encoded and are unsuitable for storage in Git repositories. Sealed Secrets encrypt sensitive values using the cluster's public key before they are committed to version control. The Sealed Secrets controller decrypts them within the cluster using its private key, allowing GitOps workflows while ensuring credentials remain protected.

---

These architectural decisions resulted in a deployment that is reproducible, secure, highly available, and fully managed through Infrastructure as Code and GitOps, while remaining simple enough to operate within the constraints of a three-node Kubernetes cluster.
