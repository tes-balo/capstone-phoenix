# Runbook — Capstone Phoenix
> A teammate must be able to rebuild this entire stack from zero using only this document.

---

## Provision from zero

---

### Prerequisites

Before touching any Terraform, ensure the following are in place on your local machine:

**Tools required:**
```bash
terraform -v        # >= 1.5.0
az --version        # Azure CLI, any recent version
ssh -V              # OpenSSH
```

**Azure login:**
```bash
az login
az account show     # confirm correct subscription is active
```

**Get your current public IP — you'll need this for tfvars:**
```bash
curl ifconfig.me
```

---

### Step 1 — Generate SSH Key (RSA only)

> ⚠️ Azure's Terraform provider v3.x only accepts RSA keys. ed25519 will be rejected at `terraform apply`.

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/capstone-phoenix-azure -C "capstone-phoenix-azure"
```

This creates:
- `~/.ssh/capstone-phoenix-azure` — private key (never share)
- `~/.ssh/capstone-phoenix-azure.pub` — public key (used in tfvars)

---

### Step 2 — Check VM Quota

> ⚠️ Azure B-series v1 (B2s, B1ms) may show as available but fail with capacity errors at apply time. Always use B-series v2.

Check available B-series SKUs in your target region:
```bash
az vm list-skus --location swedencentral --size Standard_B --query "[?restrictions==[]].name" -o table
```

Check your current vCPU quota:
```bash
az vm list-usage --location swedencentral --query "[?contains(name.value, 'cores')].{Name:name.localizedValue, Current:currentValue, Limit:limit}" -o table
```

You need at least **6 vCPUs** available for 3 VMs (1x `Standard_B2s_v2` + 2x `Standard_B2ls_v2`).

If quota is insufficient, request an increase via the Azure portal:
> Portal → Subscriptions → Usage + Quotas → Request Increase → select "Standard Bsv2 Family vCPUs"

---

### Step 3 — Configure tfvars

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_name        = "capstone-phoenix"
resource_group_name = "capstone-phoenix-rg"
location            = "swedencentral"
subscription_id     = "<your-azure-subscription-id>"   # from: az account show
my_ip               = "<your-public-ip>/32"             # from: curl ifconfig.me — include the /32
ssh_public_key_path = "~/.ssh/capstone-phoenix-azure.pub"
server_vm_size      = "Standard_B2s_v2"
worker_vm_size      = "Standard_B2ls_v2"
```

> ⚠️ `my_ip` changes if your ISP assigns a dynamic IP. Always run `curl ifconfig.me` before applying and update tfvars if it has changed. Stale IP = locked out of SSH and k3s API.

> ⚠️ Never commit `terraform.tfvars` — it contains your IP and subscription ID.

---

### Step 4 — Initialise Terraform

```bash
cd infra/terraform
terraform init
```

Expected output: `Terraform has been successfully initialized!`

This downloads the `hashicorp/azurerm ~> 3.0` provider. Commit `.terraform.lock.hcl` to version control.

---

### Step 5 — Plan

```bash
terraform plan -out=capstone-phoenix-infra-plan-v1
```

Expected: `Plan: 21 to add, 0 to change, 0 to destroy`

Resources created:
- 1 Resource Group
- 1 VNet + 1 Subnet
- 1 NSG + 5 NSG rules (http, https, ssh, k3s_api, internal)
- 3 Public IPs (Static, Standard SKU)
- 3 NICs
- 3 NIC-NSG associations
- 3 Linux VMs (Ubuntu 22.04)

> ⚠️ Saved plan files go stale if state changes. If you ran a partial apply before, discard the saved plan and run `terraform apply` directly instead — Terraform will replan from current state automatically.

---

### Step 6 — Apply

```bash
terraform apply "capstone-phoenix-infra-plan-v1"
```

Type `yes` when prompted.

Expected output at completion:
```
Apply complete! Resources: 21 added, 0 changed, 0 destroyed.

Outputs:
control_plane_public_ip  = "<ip>"
control_plane_private_ip = "<ip>"
worker_public_ip         = ["<ip>", "<ip>"]
```

Note down all 3 public IPs and the control plane private IP — you will need them for Ansible.

---

### Step 7 — Verify SSH Access

Test all 3 nodes before proceeding:

```bash
ssh -i ~/.ssh/capstone-phoenix-azure tes@<control_plane_public_ip>
ssh -i ~/.ssh/capstone-phoenix-azure tes@<worker_0_public_ip>
ssh -i ~/.ssh/capstone-phoenix-azure tes@<worker_1_public_ip>
```

Expected: Ubuntu 22.04 welcome message on each node. Exit each with `exit`.

If SSH is refused:
1. Check your current IP has not changed: `curl ifconfig.me`
2. Compare against `my_ip` in tfvars
3. If different, update tfvars and run `terraform apply` to update the NSG rule

---

### Step 8 — Enable NIC IP Forwarding (Azure-specific — CRITICAL, do not skip)

> ⚠️ Azure disables IP forwarding on all NICs by default. Without this, Calico cannot forward packets from the node NIC to pod IPs. Cross-node pod networking will be silently broken — pods appear healthy but cannot communicate across nodes. This is not visible in NSG logs or Calico logs. Enable this immediately after terraform apply, before Ansible.

```bash
az network nic update \
  --resource-group capstone-phoenix-rg \
  --name capstone-phoenix-control-plane-nic \
  --ip-forwarding true

az network nic update \
  --resource-group capstone-phoenix-rg \
  --name capstone-phoenix-worker-0-nic \
  --ip-forwarding true

az network nic update \
  --resource-group capstone-phoenix-rg \
  --name capstone-phoenix-worker-1-nic \
  --ip-forwarding true
```

Verify all three show true:
```bash
az network nic list \
  --resource-group capstone-phoenix-rg \
  --query "[].{NIC:name,IPForwarding:enableIPForwarding}"
```

---

### Step 9 — Cluster Setup (Ansible)

Update `infra/ansible/inventory.ini` with the IPs from Terraform outputs:

```ini
[server]
control_plane ansible_host=<control_plane_public_ip> private_ip=<control_plane_private_ip>

[agents]
worker_0 ansible_host=<worker_0_public_ip> private_ip=10.0.1.5
worker_1 ansible_host=<worker_1_public_ip> private_ip=10.0.1.6

[k3s_cluster:children]
server
agents
```

Run the full playbook:
```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
```

This runs in order:
1. `hardening.yml` — disables root login, installs UFW, opens required ports
2. `k3s_server.yml` — installs k3s with `--flannel-backend=none --cluster-init --tls-san=<public_ip>`
3. `k3s_agents.yml` — fetches join token from control plane, joins both workers
4. `kubeconfig.yml` — fetches kubeconfig to `~/.kube/config`, rewrites server to public IP

> ⚠️ The `k3s_agents.yml` playbook will appear to hang after the install task. This is expected — k3s-agent waits for CNI to initialize before completing. Press Ctrl+C once both workers show `activating (start)` in `systemctl status k3s-agent`. The install succeeded.

Verify:
```bash
kubectl get nodes
# Should show 3 nodes all in Ready state
```

> ⚠️ Nodes show `NotReady` immediately after k3s install until Calico is installed. This is correct — no CNI is running yet.

---

### Step 10 — Install Calico CNI and Switch to VXLAN (CRITICAL)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait ~60 seconds for nodes to flip to Ready:
```bash
kubectl get nodes -w
```

**Immediately patch Calico from IPIP to VXLAN.** Azure silently drops IP protocol 4 (IPIP) between VMs at the network fabric level. This breaks all cross-node pod networking with no obvious error messages. VXLAN uses UDP 4789 which Azure routes correctly.

```bash
kubectl patch ippool default-ipv4-ippool \
  --type=merge \
  -p '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'

kubectl rollout restart daemonset calico-node -n kube-system
kubectl rollout status daemonset calico-node -n kube-system
```

Verify cross-node networking before proceeding:
```bash
kubectl run net-test --restart=Never --image=busybox:1.36 -n default -- sleep 300
COREDNS_IP=$(kubectl get pod -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')
kubectl exec -it net-test -- ping -c 3 $COREDNS_IP
# Must see replies, not 100% packet loss
kubectl delete pod net-test
```

> ⚠️ Do not proceed until cross-node connectivity is confirmed. DNS resolution and the migration Job both depend entirely on it.

---

### Step 11 — Deploy Kubernetes Manifests

Order matters — deploy in this exact sequence.

```bash
cd manifests/

# Foundation
kubectl apply -f namespace.yaml
kubectl apply -f backend-config.yaml
kubectl apply -f backend-secret.yaml    # populate real values first — never commit

# Postgres — wait for it to be Running before continuing
kubectl apply -f postgres-service.yaml
kubectl apply -f postgres-statefulset.yaml
kubectl get pods -n taskapp -w
# Wait for: postgres-0   1/1   Running

# Migration Job — must complete before backend starts
kubectl apply -f taskapp-migrate.yaml
kubectl get job -n taskapp taskapp-migrate -w
# Wait for: COMPLETIONS 1/1   STATUS Complete

# Application
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml

# Verify spread across nodes
kubectl get pods -n taskapp -o wide
# backend replicas: different nodes
# frontend replicas: different nodes
```

---

### Step 12 — Platform: cert-manager and Ingress/TLS

DNS A records must exist before cert-manager can issue a certificate. In AWS Route 53, create:
```
taskapp.<your-domain>    A    <control_plane_public_ip>
api.<your-domain>        A    <control_plane_public_ip>
```

Verify propagation:
```bash
nslookup taskapp.<your-domain> 8.8.8.8
nslookup api.<your-domain> 8.8.8.8
# Both must return the control plane public IP before proceeding
```

Install cert-manager:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager \
  --timeout=300s
```

Apply ClusterIssuer and Ingress:
```bash
kubectl apply -f cert-manager-issuer.yaml
kubectl apply -f ingress.yaml
```

Watch for certificate issuance (~60 seconds):
```bash
kubectl get certificate -n taskapp -w
# Wait for: READY True
```

Verify TLS:
```bash
curl -vI https://taskapp.<your-domain> 2>&1 | grep -E "subject|issuer|SSL"
```

---

### Step 13 — GitOps (Argo CD)

> To be documented after the GitOps session. Placeholder:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f gitops/
# Argo CD syncs the app — no more manual kubectl apply for app manifests from this point
```

---

## Day-2 Operations

### Scale a tier
Prefer a git commit so Argo CD stays the source of truth. Manual scaling creates drift and Argo will revert it on next sync.

```bash
# Preferred — via git:
# Edit replicas in the relevant Deployment manifest, commit and push

# Emergency manual scale only:
kubectl scale deployment backend -n taskapp --replicas=3
kubectl scale deployment frontend -n taskapp --replicas=3
```

---

### Roll back a bad deploy

```bash
# Preferred — via git revert:
git revert <bad-commit-sha>
git push
# Argo CD reconciles automatically

# Emergency kubectl rollback:
kubectl rollout undo deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp

# Check history to pick a specific revision:
kubectl rollout history deployment/backend -n taskapp
kubectl rollout undo deployment/backend -n taskapp --to-revision=<N>
```

---

### Run a new migration safely

> ⚠️ Never run migrations inside the Deployment at 2+ replicas — pods race on `alembic upgrade head`. Always use a Job.

```bash
# Step 1: scale backend to 0
kubectl scale deployment backend -n taskapp --replicas=0

# Step 2: delete the old completed Job (Jobs are immutable — cannot reapply)
kubectl delete job taskapp-migrate -n taskapp

# Step 3: apply the new migration Job
kubectl apply -f taskapp-migrate.yaml

# Step 4: wait for completion
kubectl get job -n taskapp taskapp-migrate -w

# Step 5: scale backend back up
kubectl scale deployment backend -n taskapp --replicas=2
kubectl rollout status deployment/backend -n taskapp
```

---

### Rotate a secret

> ⚠️ The `type` field on a Kubernetes Secret is immutable. Patching it (even to fix a typo) is rejected. You must delete and recreate.

```bash
# Update values in backend-secret.yaml locally
kubectl delete secret backend-secret -n taskapp
kubectl apply -f backend-secret.yaml

# Rolling restart so pods reload the new secret at next startup
kubectl rollout restart deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp
```

> ⚠️ Deleting the Secret while pods are running does not immediately break them — env vars are already in memory. The risk is a pod restart between delete and recreate. Scale to 0 first if you need safety.

---

## Failure Recovery

### A worker node dies or is drained

**What Kubernetes does automatically:**
- Detects NodeNotReady after ~40-60 seconds
- Evicts and reschedules pods on remaining healthy nodes
- Removes dead-node pods from Service endpoints
- With `topologySpreadConstraints: maxSkew: 1` and 2 replicas, one replica was already on a different node — zero downtime if spread was working

**What you do:**

```bash
kubectl get nodes

# For planned maintenance:
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# --ignore-daemonsets: skips Calico/system DaemonSet pods (expected)
# --delete-emptydir-data: allows evicting pods using emptyDir volumes

kubectl get pods -n taskapp -o wide -w   # watch rescheduling

# When maintenance is done:
kubectl uncordon <node-name>
```

Node names in this cluster:
```
capstone-phoenix-control-plane-vm
capstone-phoenix-worker-0-vm
capstone-phoenix-worker-1-vm
```

Expected recovery time: 1-2 minutes. Zero dropped requests if topology spread was working.

> ⚠️ Always verify replica spread with `kubectl get pods -n taskapp -o wide` after deployments. If both backend replicas are on the same node and that node dies, both replicas go down simultaneously despite having "2 replicas."

---

### A backend Pod crashloops

```bash
# Check status
kubectl get pods -n taskapp
# CrashLoopBackOff or high RESTARTS count = crashing

# Current logs
kubectl logs -n taskapp <pod-name>

# Logs from previous crash — most useful
kubectl logs -n taskapp <pod-name> --previous

# Full event history
kubectl describe pod -n taskapp <pod-name>
# Key sections: Events (bottom), Last State, Containers > State

# Test the health endpoint from inside the cluster
kubectl run debug --rm -it --restart=Never --image=curlimages/curl -n taskapp -- \
  curl -v http://backend:5000/api/healthz
```

Common causes:

| Symptom | Cause | Fix |
|---|---|---|
| OOMKilled | Memory limit too low | Increase `resources.limits.memory` |
| Readiness probe failed | App not ready in time | Increase `initialDelaySeconds` |
| secret not found | Secret missing or wrong namespace | Recreate the Secret |
| could not translate host name | DNS/cross-node broken | Fix Calico VXLAN |
| password authentication failed | Wrong DB credentials | Rotate the Secret |

---

### A bad migration

```bash
# Step 1: scale backend to 0
kubectl scale deployment backend -n taskapp --replicas=0

# Step 2: open a shell with the backend image and same env vars
kubectl run migration-debug \
  --rm -it \
  --restart=Never \
  --image=ghcr.io/ts-a-devops/taskapp-backend:5d6b8fc \
  -n taskapp \
  -- bash

# Step 3: inspect and downgrade
alembic current
alembic history
alembic downgrade -1          # go back one revision
# or: alembic downgrade <revision-id>

# Step 4: scale backend back up
exit
kubectl scale deployment backend -n taskapp --replicas=2
kubectl rollout status deployment/backend -n taskapp
```

> ⚠️ The debug pod may not automatically have DATABASE_* env vars. Run `env | grep DATABASE` to check. If missing, pass them with `--env` flags or exec directly into the postgres pod with psql.

---

### Postgres Pod is rescheduled — prove PVC re-attaches and data is intact

```bash
# Step 1: write test data
kubectl exec -it postgres-0 -n taskapp -- \
  psql -U <DATABASE_USER> -d taskapp \
  -c "INSERT INTO tasks (title) VALUES ('pvc-reattach-test');"

# Step 2: kill the pod — StatefulSet recreates it (possibly on a different node)
kubectl delete pod postgres-0 -n taskapp

# Step 3: watch it come back
kubectl get pods -n taskapp -o wide -w
# Wait for: postgres-0   1/1   Running

# Step 4: verify data survived
kubectl exec -it postgres-0 -n taskapp -- \
  psql -U <DATABASE_USER> -d taskapp \
  -c "SELECT * FROM tasks WHERE title = 'pvc-reattach-test';"
# Row must still be there

# Verify PVC is still bound
kubectl get pvc -n taskapp
# postgres-storage-postgres-0   Bound
```

---

## Known Issues and Fixes

### Calico cross-node pod networking broken (Azure IPIP silent drop)

> ⚠️ The most dangerous failure mode in this project. Everything looks healthy but cross-node traffic silently dies.

**Symptoms:**
- `kubectl get nodes` shows all 3 nodes Ready (misleading)
- Same-node pod-to-pod works fine
- Cross-node pod-to-pod silently fails — ping hangs, 100% packet loss
- DNS resolution fails — nslookup times out (CoreDNS is on a different node)
- Migration Job stuck in `Init:0/1` — initContainer cannot reach Postgres by hostname
- `pg_isready -h postgres.taskapp.svc.cluster.local` returns "no response" but `pg_isready -h <pod-ip>` works
- BusyBox test pod: `nslookup kubernetes.default.svc.cluster.local` connection timed out

**Root cause:** Calico defaults to `ipipMode: Always`. Azure drops IP protocol 4 (IPIP) at the network fabric level, not at the NSG. Even `protocol: *` NSG rules do not prevent this drop.

**Diagnosis:**
```bash
kubectl get ippool default-ipv4-ippool -o yaml | grep -E "ipipMode|vxlanMode"
# ipipMode: Always = the problem

# Confirm cross-node failure specifically
kubectl run net-test --restart=Never --image=busybox:1.36 -n taskapp -- sleep 300
COREDNS_IP=$(kubectl get pod -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')
kubectl exec -it net-test -n taskapp -- ping -c 3 $COREDNS_IP
# 100% packet loss = IPIP cross-node failure confirmed
kubectl delete pod net-test -n taskapp
```

**Fix:**
```bash
kubectl patch ippool default-ipv4-ippool \
  --type=merge \
  -p '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'

kubectl rollout restart daemonset calico-node -n kube-system
kubectl rollout status daemonset calico-node -n kube-system

# Verify fix
kubectl run net-test --restart=Never --image=busybox:1.36 -n taskapp -- sleep 300
kubectl exec -it net-test -n taskapp -- ping -c 3 $COREDNS_IP
# Should now show replies
kubectl delete pod net-test -n taskapp
```

**Why VXLAN works:** IPIP wraps packets in raw IP protocol 4. Azure drops protocol 4 between VMs. VXLAN wraps packets in UDP 4789. Azure routes UDP without issues.

**Prevention:** Always apply the VXLAN patch immediately after installing Calico on Azure. This is Step 10 above and must not be skipped on any rebuild.

---

### NIC IP forwarding disabled (Azure default)

**Symptoms:** Similar to IPIP issue — cross-node pod communication fails.

**Diagnosis:**
```bash
az network nic list \
  --resource-group capstone-phoenix-rg \
  --query "[].{NIC:name,IPForwarding:enableIPForwarding}"
# Any false = problem
```

**Fix:** See Step 8. Enable IP forwarding on all 3 NICs.

> ⚠️ In this project both NIC IP forwarding AND the IPIP issue were present simultaneously. Enabling IP forwarding alone did not fix cross-node networking — the VXLAN patch was also required. Apply both fixes.

---

### Dynamic IP lockout (recurring)

**Symptom:**
```
Unable to connect to the server: dial tcp 4.223.110.248:6443: i/o timeout
ssh: connect to host 4.223.110.248 port 22: Connection timed out
```

**Cause:** ISP assigned a new public IP. NSG rules for SSH (22) and k3s API (6443) are tied to the old IP.

**Fix:**
```bash
curl ifconfig.me   # get current IP
# Update my_ip in infra/terraform/terraform.tfvars
# Run:
cd infra/terraform
terraform apply -auto-approve
# Only the NSG rule updates — nothing else changes
```

Or use the `update_ip.sh` script which does this automatically.

> ⚠️ Run `curl ifconfig.me` at the start of every session and compare to `my_ip` in tfvars before doing anything else.

---

### Migration Job stuck in Init:0/1

**Cause:** The `wait-for-postgres` initContainer is looping on `pg_isready` but cannot reach Postgres.

**Diagnosis:**
```bash
kubectl logs -n taskapp <migrate-pod-name> -c wait-for-postgres
# "postgres:5432 - no response" = DNS resolving but TCP failing (cross-node issue)
# "could not translate host name" = DNS not resolving (cross-node or CoreDNS down)

# Test direct pod IP
POSTGRES_IP=$(kubectl get pod postgres-0 -n taskapp -o jsonpath='{.status.podIP}')
kubectl exec -n taskapp <migrate-pod-name> -c wait-for-postgres -- \
  pg_isready -h $POSTGRES_IP -p 5432
# If this works but hostname fails = cross-node DNS issue
```

**Fix:** Resolve Calico VXLAN issue. If Postgres just is not ready yet, the initContainer retries automatically every 2 seconds.

> ⚠️ Always use the full DNS name `postgres.taskapp.svc.cluster.local` in the initContainer command, not just `postgres`. The short name can fail to resolve in some pod startup timing windows even when the full name works.

---

### Migration Job failed (COMPLETIONS: 0/1, STATUS: Failed)

```bash
# Get logs while pod still exists
kubectl logs -n taskapp -l job-name=taskapp-migrate -c migrate

# Must delete and recreate — cannot reapply a failed Job
kubectl delete job -n taskapp taskapp-migrate
# Fix the underlying cause first
kubectl apply -f taskapp-migrate.yaml
```

---

### Secret type immutable

**Symptom:**
```
The Secret "backend-secret" is invalid: type: Invalid value: "Opaque": field is immutable
```

**Fix:**
```bash
kubectl delete secret -n taskapp backend-secret
kubectl apply -f backend-secret.yaml
```

Safe only when no pods are depending on it. Scale Deployments to 0 first if needed.

---

### cert-manager ClusterIssuer indentation error

**Symptom:** ClusterIssuer applies successfully but no `cm-acme-http-solver-*` Ingresses appear. Certificate stays NotReady.

**Cause:** Wrong YAML indentation in the solvers block. `ingress:` must be nested under `http01:`, not at the same level.

Incorrect:
```yaml
    solvers:
      - http01:
        ingress:
          class: traefik
```

Correct:
```yaml
    solvers:
      - http01:
          ingress:
            class: traefik
```

**Fix:** Edit the file, reapply the issuer, delete and recreate the Ingress to force cert-manager to reprocess it.

---

### Resource group 404 errors on first apply

**Symptom:** NSG rules or NICs fail with ResourceNotFound immediately after the resource group is created.

**Fix:** Re-run `terraform apply`. The `depends_on` blocks handle this on subsequent runs.

---

### VM capacity errors (SkuNotAvailable)

**Fix:** Use B-series v2. Update tfvars to `Standard_B2s_v2` and `Standard_B2ls_v2`. Check available SKUs:
```bash
az vm list-skus --location swedencentral --size Standard_B --query "[?restrictions==[]].name" -o table
```

---

### Destroy fails — resource group still contains resources

**Fix:** The provider already has `prevent_deletion_if_contains_resources = false`. Just re-run:
```bash
terraform destroy -auto-approve
```

---

## Clean Destroy and Rebuild Cycle

```bash
terraform destroy -auto-approve && sleep 120 && terraform apply -auto-approve
```

The `sleep 120` gives Azure time to fully deprovision before recreating. After `terraform apply`, follow Steps 8 through 12 again. Steps 8 (NIC IP forwarding) and 10 (Calico VXLAN patch) are the easiest to forget on a rebuild — do not skip them.

---

## Quick Reference

```bash
# Cluster health
kubectl get nodes
kubectl get pods -n taskapp -o wide
kubectl get all -n taskapp

# Logs
kubectl logs -n taskapp <pod-name>
kubectl logs -n taskapp <pod-name> --previous
kubectl logs -n taskapp <pod-name> -c <container>

# Describe
kubectl describe pod -n taskapp <pod-name>
kubectl describe node <node-name>

# TLS
kubectl get certificate -n taskapp
kubectl describe certificate taskapp-tls -n taskapp
kubectl get challenges -n taskapp

# Exec
kubectl exec -it -n taskapp <pod-name> -- bash
kubectl exec -it -n taskapp <pod-name> -c <container> -- sh

# Watch live
kubectl get pods -n taskapp -w

# Resource usage
kubectl top pods -n taskapp
kubectl top nodes

# Jobs
kubectl get job -n taskapp
kubectl delete job -n taskapp taskapp-migrate

# Networking debug
kubectl run net-test --restart=Never --image=busybox:1.36 -n taskapp -- sleep 300
kubectl exec -it net-test -n taskapp -- nslookup postgres
kubectl exec -it net-test -n taskapp -- nslookup kubernetes.default.svc.cluster.local
kubectl delete pod net-test -n taskapp
```

---

## Infrastructure Summary

| Resource | Name | Value |
|----------|------|-------|
| Resource Group | `capstone-phoenix-rg` | Sweden Central |
| VNet | `capstone-phoenix-vnet` | `10.0.0.0/16` |
| Subnet | `capstone-phoenix-subnet` | `10.0.1.0/24` |
| NSG | `capstone-phoenix-nsg` | 5 inbound rules |
| Control Plane VM | `capstone-phoenix-control-plane-vm` | `Standard_B2s_v2` |
| Worker VMs | `capstone-phoenix-worker-{0,1}-vm` | `Standard_B2ls_v2` |
| Admin user | `tes` | SSH key auth only |
| OS | Ubuntu 22.04 LTS | `22_04-lts-gen2` |
| SSH Key type | RSA 4096 | Azure requires RSA — ed25519 rejected in azurerm v3 |
| Control plane public IP | `4.223.110.248` | NSG, kubeconfig, DNS |
| Worker 0 public IP | `20.91.197.134` | Ansible target |
| Worker 1 public IP | `51.12.86.216` | Ansible target |
| Frontend URL | `https://taskapp.tesbuilds.fun` | Let's Encrypt TLS |
| Backend URL | `https://api.tesbuilds.fun` | Let's Encrypt TLS |
| DNS provider | AWS Route 53 | Hosted zone for tesbuilds.fun |
| Calico encapsulation | VXLAN (UDP 4789) | NOT IPIP — Azure drops IPIP silently |
| Backend image | `ghcr.io/ts-a-devops/taskapp-backend:5d6b8fc` | Pinned SHA |
| Frontend image | `ghcr.io/ts-a-devops/taskapp-frontend:26da2b0` | Pinned SHA |
| Postgres image | `postgres:16.14` | Pinned minor version |
| TLS cert expiry | `2026-10-01` | Auto-renews via cert-manager ~30 days before |