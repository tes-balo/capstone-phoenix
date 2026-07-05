# Runbook — Capstone Phoenix
> A teammate must be able to rebuild this entire stack from zero using only this document.

---

## Provision from zero

### Prerequisites
- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.5.0 installed
- Ansible >= 2.16 installed
- SSH key generated (RSA, not ed25519 — Azure requirement):
  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/capstone-phoenix-azure
  ```
- `terraform.tfvars` populated (never commit this file):
  ```hcl
  project_name        = "capstone-phoenix"
  my_ip               = "<your-current-ip>/32"   # run: curl ifconfig.me
  location            = "swedencentral"
  ssh_public_key_path = "~/.ssh/capstone-phoenix-azure.pub"
  server_vm_size      = "Standard_B2s_v2"
  worker_vm_size      = "Standard_B2ls_v2"
  subscription_id     = "590fe946-a55a-489f-b284-f020e7877948"
  resource_group_name = "capstone-phoenix-rg"
  ```

---

### Step 1 — Infrastructure (Terraform)
```bash
cd infra/terraform
terraform init
terraform apply
```

Expected output: 21 resources created in Sweden Central (resource group, VNet, subnet, NSG + 5 rules, 3 public IPs, 3 NICs, 3 NIC-NSG associations, 3 VMs).

Note the outputs — control plane and worker public IPs. Update `infra/ansible/inventory.ini` if they differ from:
```
control_plane: 4.223.110.248
worker_0:      20.91.197.134
worker_1:      51.12.86.216
```

**After provisioning — enable NIC IP forwarding on all 3 VMs** (required for Calico pod networking on Azure):
```bash
az network nic update --resource-group capstone-phoenix-rg --name capstone-phoenix-control-plane-nic --ip-forwarding true
az network nic update --resource-group capstone-phoenix-rg --name capstone-phoenix-worker-0-nic --ip-forwarding true
az network nic update --resource-group capstone-phoenix-rg --name capstone-phoenix-worker-1-nic --ip-forwarding true
```

Verify:
```bash
az network nic list --resource-group capstone-phoenix-rg \
  --query "[].{NIC:name,IPForwarding:enableIPForwarding}"
# All three should show IPForwarding: true
```

---

### Step 2 — Cluster setup (Ansible)
```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/site.yml
```

This runs in order: hardening → k3s_server → k3s_agents → kubeconfig.

Expected result: kubeconfig written to `~/.kube/config` with server address pointing at the control plane public IP.

Verify:
```bash
kubectl get nodes
# Should show 3 nodes in Ready state
```

---

### Step 3 — Install Calico CNI and fix encapsulation

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait ~60 seconds for nodes to flip from `NotReady` → `Ready`, then **immediately patch IPIP to VXLAN** (critical on Azure — IPIP is silently dropped by Azure's network fabric):

```bash
kubectl patch ippool default-ipv4-ippool \
  --type=merge \
  -p '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'

kubectl rollout restart daemonset calico-node -n kube-system
kubectl rollout status daemonset calico-node -n kube-system
```

Verify cross-node networking works:
```bash
kubectl run net-test --restart=Never --image=busybox:1.36 -n default -- sleep 300
kubectl get pod net-test -o wide   # note which node it lands on
# From another pod on a different node, ping this pod's IP
# If ping succeeds, cross-node networking is working
kubectl delete pod net-test
```

---

### Step 4 — Apply Kubernetes manifests

```bash
cd manifests/
kubectl apply -f namespace.yaml
kubectl apply -f backend-config.yaml
kubectl apply -f backend-secret.yaml      # populate real values first — never commit
kubectl apply -f postgres-service.yaml
kubectl apply -f postgres-statefulset.yaml
```

Wait for Postgres to be ready:
```bash
kubectl get pods -n taskapp -w
# Wait for postgres-0 to show 1/1 Running
```

Run migrations (once, before backend starts):
```bash
kubectl apply -f taskapp-migrate.yaml
kubectl get job -n taskapp taskapp-migrate
# Wait for COMPLETIONS: 1/1
```

Deploy application:
```bash
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
```

---

### Step 5 — Platform (cert-manager + Ingress)

Install cert-manager:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=300s
```

Create ClusterIssuer and Ingress:
```bash
kubectl apply -f cert-manager-issuer.yaml
kubectl apply -f ingress.yaml
```

Verify certificate is issued (takes ~60 seconds):
```bash
kubectl get certificate -n taskapp
# Should show READY: True
```

Verify TLS is working:
```bash
curl -vI https://taskapp.tesbuilds.fun 2>&1 | grep -E "subject|issuer|SSL"
```

---

### Step 6 — GitOps (Argo CD)

Install Argo CD:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s
```

Apply Argo CD application (from `gitops/` directory):
```bash
kubectl apply -f gitops/
# Argo CD syncs the app — no more manual kubectl apply for app manifests
```

From this point, all changes to the app go through git commits. Argo CD reconciles the live cluster to match the repo state automatically.

---

## Day-2 Operations

### Scale a tier
Prefer a git commit so Argo stays the source of truth:
```bash
# Edit the replicas field in backend-deployment.yaml or frontend-deployment.yaml
# Then commit and push — Argo CD will apply automatically

# Emergency manual scale (use sparingly — creates drift from git):
kubectl scale deployment backend -n taskapp --replicas=3
```

---

### Roll back a bad deploy
```bash
# Via git (preferred — keeps Argo in sync):
git revert <bad-commit-sha>
git push
# Argo CD detects the change and rolls back automatically

# Via kubectl (emergency only):
kubectl rollout undo deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp

# Check rollout history:
kubectl rollout history deployment/backend -n taskapp
```

---

### Run a new migration safely
Migrations must always run as a Job, never in the Deployment entrypoint at scale. The correct process:

1. Scale backend replicas to 0 (prevent new requests during migration):
   ```bash
   kubectl scale deployment backend -n taskapp --replicas=0
   ```
2. Delete the old completed migration Job (Jobs are immutable once created):
   ```bash
   kubectl delete job taskapp-migrate -n taskapp
   ```
3. Apply the new migration Job:
   ```bash
   kubectl apply -f taskapp-migrate.yaml
   ```
4. Wait for completion:
   ```bash
   kubectl get job -n taskapp taskapp-migrate
   # Wait for COMPLETIONS: 1/1
   ```
5. Scale backend back up:
   ```bash
   kubectl scale deployment backend -n taskapp --replicas=2
   ```

---

### Rotate a secret
Kubernetes `type` on a Secret is immutable — you must delete and recreate, not patch:

```bash
# Update values in backend-secret.yaml locally (never commit plaintext secrets)
kubectl delete secret backend-secret -n taskapp
kubectl apply -f backend-secret.yaml

# Rolling restart to pick up new secret values (pods cache env vars at startup):
kubectl rollout restart deployment/backend -n taskapp
kubectl rollout status deployment/backend -n taskapp
```

**Warning:** deleting the Secret while pods are running doesn't immediately break them (env vars are already loaded in memory). The risk is if a pod restarts between delete and recreate — it'll fail to start. Delete and recreate quickly, or briefly scale to 0 first.

---

## Failure Recovery

### A worker node dies or is drained
**What happens automatically:**
- Kubernetes detects node is unavailable (takes ~40-60 seconds for `NodeNotReady`)
- Pods on the dead node are evicted and rescheduled on remaining healthy nodes
- The Service automatically stops routing to pods on the dead node once they fail readiness probes
- With `topologySpreadConstraints: maxSkew: 1` and 2 replicas, one replica was already on a different node — so one replica survives immediately with zero downtime

**What you do:**
```bash
# Check node status
kubectl get nodes

# If deliberately draining a node for maintenance:
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# --ignore-daemonsets: don't evict Calico/system DaemonSet pods
# --delete-emptydir-data: allows evicting pods that use emptyDir volumes

# Verify pods rescheduled elsewhere:
kubectl get pods -n taskapp -o wide

# When node is back / maintenance is done:
kubectl uncordon <node-name>
```

**Expected recovery time:** 1-2 minutes for pod rescheduling. Zero dropped requests if `topologySpreadConstraints` was working correctly (one replica was on a different node already).

**Node names in this cluster:**
```
capstone-phoenix-control-plane-vm
capstone-phoenix-worker-0-vm
capstone-phoenix-worker-1-vm
```

---

### A backend Pod crashloops
**Diagnosis workflow:**
```bash
# Step 1: see what's happening
kubectl get pods -n taskapp
# Look for STATUS: CrashLoopBackOff, Error, or high RESTARTS count

# Step 2: check current logs
kubectl logs -n taskapp <pod-name>

# Step 3: check logs from the previous crash (before it restarted)
kubectl logs -n taskapp <pod-name> --previous

# Step 4: full event history — often shows OOMKilled, probe failures, etc.
kubectl describe pod -n taskapp <pod-name>
# Look at: Events section at the bottom, Last State, containers status

# Step 5: if probe is failing, test the endpoint manually from inside the cluster
kubectl run debug --rm -it --restart=Never --image=curlimages/curl -n taskapp -- \
  curl http://backend:5000/api/healthz
```

**Common causes and fixes:**
- **OOMKilled:** container exceeded memory limit. Increase `resources.limits.memory` in `backend-deployment.yaml`, commit, push (Argo will apply).
- **Readiness probe failing:** app not starting up in time. Increase `initialDelaySeconds` on the readiness probe.
- **Database connection error:** check ConfigMap values (`DATABASE_HOST`, `DATABASE_PORT`) and Secret values (`DATABASE_USER`, `DATABASE_PASSWORD`). Verify Postgres pod is `1/1 Running`.
- **Missing env var:** check `kubectl describe pod` for `Error: secret "backend-secret" not found` or similar.

---

### A bad migration
**Scenario:** A migration ran but broke the schema or corrupted data.

```bash
# Step 1: immediately scale backend to 0 — stop all traffic to the broken schema
kubectl scale deployment backend -n taskapp --replicas=0

# Step 2: get a shell inside a temporary pod with the backend image
kubectl run migration-debug \
  --rm -it \
  --restart=Never \
  --image=ghcr.io/ts-a-devops/taskapp-backend:5d6b8fc \
  -n taskapp \
  --env-from=configmap/backend-config \
  --env-from=secret/backend-secret \
  -- bash

# Step 3: inside the pod, check current migration state
alembic current
alembic history

# Step 4: downgrade to previous version
alembic downgrade -1     # go back one revision
# or target a specific revision:
alembic downgrade <revision-id>

# Step 5: exit the debug pod, scale backend back up to the previous image tag
kubectl scale deployment backend -n taskapp --replicas=2
```

**Prevention:** always test migrations on a dev/staging database before running on production. The migration Job's `backoffLimit: 3` means it retries 3 times before failing — if a migration fails 3 times, fix the migration code, delete the Job, and reapply.

---

### Postgres Pod is rescheduled — prove PVC re-attaches and data is intact

This is the StatefulSet guarantee: `postgres-0` always gets the same PVC (`postgres-storage-postgres-0`) regardless of which node it lands on.

**Simulate it:**
```bash
# Step 1: write some test data first
kubectl exec -it postgres-0 -n taskapp -- psql -U <DATABASE_USER> -d taskapp \
  -c "INSERT INTO tasks (title) VALUES ('test-before-restart');"

# Step 2: kill the Postgres pod (StatefulSet will immediately recreate it)
kubectl delete pod postgres-0 -n taskapp

# Step 3: watch it come back — may reschedule on a different node
kubectl get pods -n taskapp -o wide -w

# Step 4: once 1/1 Running, verify data survived
kubectl exec -it postgres-0 -n taskapp -- psql -U <DATABASE_USER> -d taskapp \
  -c "SELECT * FROM tasks WHERE title = 'test-before-restart';"
# Row should still be there — PVC persisted across pod deletion
```

**Why it works:** The PVC (`postgres-storage-postgres-0`) is bound to a persistent volume on the cluster's storage class. When the pod is deleted, the PVC stays. When `postgres-0` is recreated (same name, StatefulSet guarantee), Kubernetes mounts the same PVC again — the data is exactly where it was left.

**Verify the PVC:**
```bash
kubectl get pvc -n taskapp
# Should show: postgres-storage-postgres-0   Bound   ...
```

---

## Networking Troubleshooting

### Check cross-node pod connectivity
```bash
kubectl run net-test --restart=Never --image=busybox:1.36 -n taskapp -- sleep 300
kubectl get pod net-test -n taskapp -o wide   # note which node

# From inside the pod, ping a pod on a different node
kubectl exec -it net-test -n taskapp -- ping <pod-ip-on-different-node>

# Check DNS works
kubectl exec -it net-test -n taskapp -- nslookup postgres
kubectl exec -it net-test -n taskapp -- nslookup kubernetes.default.svc.cluster.local

kubectl delete pod net-test -n taskapp
```

### Dynamic IP lockout (recurring issue)
Your local IP changes between sessions. When it does, the NSG rule for SSH (port 22) and kubectl (port 6443) locks you out.

**Symptom:** `dial tcp 4.223.110.248:6443: i/o timeout` from kubectl, or SSH connection timeout.

**Fix:**
```bash
# Check your current IP vs what's in tfvars
curl ifconfig.me

# Run the update script (updates tfvars + applies only the NSG rule change):
./update_ip.sh

# Or manually:
# Update my_ip in infra/terraform/terraform.tfvars
# Then:
cd infra/terraform && terraform apply -auto-approve
```

### Calico IPIP silent drop (Azure-specific — already fixed, document for reference)
If cross-node pod networking is broken but everything looks healthy in Kubernetes, check if Calico is using IPIP:
```bash
kubectl get ippool default-ipv4-ippool -o yaml | grep -E "ipipMode|vxlanMode"
```

If `ipipMode: Always` — fix immediately:
```bash
kubectl patch ippool default-ipv4-ippool \
  --type=merge \
  -p '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'
kubectl rollout restart daemonset calico-node -n kube-system
```

Azure silently drops IP protocol 4 (IPIP) between VMs. VXLAN (UDP 4789) works correctly. This is fixed in this cluster but document it because any rebuild will hit it again.

---

## Quick Reference — Useful Commands

```bash
# Cluster health
kubectl get nodes
kubectl get pods -n taskapp -o wide
kubectl get all -n taskapp

# Check logs
kubectl logs -n taskapp <pod-name>
kubectl logs -n taskapp <pod-name> --previous   # last crash
kubectl logs -n taskapp <pod-name> -c <container>  # specific container

# Describe (shows events, probe status, resource usage)
kubectl describe pod -n taskapp <pod-name>
kubectl describe node <node-name>

# Certificate status
kubectl get certificate -n taskapp
kubectl describe certificate taskapp-tls -n taskapp

# Exec into a running pod
kubectl exec -it -n taskapp <pod-name> -- bash
kubectl exec -it -n taskapp <pod-name> -c <container> -- sh

# Watch pod status live
kubectl get pods -n taskapp -w

# Check resource usage
kubectl top pods -n taskapp
kubectl top nodes

# Argo CD sync status (once installed)
kubectl get applications -n argocd
kubectl describe application taskapp -n argocd
```

---

## Environment Reference

| Resource | Value |
|---|---|
| Control plane public IP | `4.223.110.248` |
| Worker 0 public IP | `20.91.197.134` |
| Worker 1 public IP | `51.12.86.216` |
| SSH user | `tes` |
| SSH key | `~/.ssh/capstone-phoenix-azure` |
| Resource group | `capstone-phoenix-rg` |
| Namespace | `taskapp` |
| Frontend URL | `https://taskapp.tesbuilds.fun` |
| Backend URL | `https://api.tesbuilds.fun` |
| Backend image | `ghcr.io/ts-a-devops/taskapp-backend:5d6b8fc` |
| Frontend image | `ghcr.io/ts-a-devops/taskapp-frontend:26da2b0` |
| Postgres image | `postgres:16.14` |
| TLS cert expires | `2026-10-01` (auto-renews via cert-manager) |
| DNS provider | AWS Route 53 |
| Calico encapsulation | VXLAN (UDP 4789) — NOT IPIP |