# Infrastructure Runbook — Terraform + Ansible

Provisions the `mega` EKS cluster on AWS (us-west-2) and configures ArgoCD,
ALB Ingress Controller, and kube-prometheus-stack via Ansible.

---

## Prerequisites

Install these tools before running anything.

```bash
# Terraform
# Download from https://developer.hashicorp.com/terraform/downloads
terraform -version        # must be >= 1.6.0

# AWS CLI v2
aws --version             # must be v2
aws configure             # set Access Key, Secret Key, region: us-west-2

# kubectl
kubectl version --client

# Helm
helm version              # must be >= 3.x

# Python 3 + pip (for Ansible)
python3 --version
pip3 --version

# Ansible
pip3 install ansible
ansible --version         # must be >= 2.14

# Ansible Kubernetes collection
ansible-galaxy collection install -r ansible/requirements.yml

# kubernetes Python SDK (required by kubernetes.core)
pip3 install kubernetes
```

---

## Step 1 — Terraform: Provision EKS Cluster

### 1.1 — Configure S3 backend (one-time setup)

Before `terraform init`, create the S3 bucket and DynamoDB table for state:

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning on the bucket
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

Then update `terraform/backend.tf` with your actual bucket name.

---

### 1.2 — Prepare variables

```bash
cd infra/terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if you want to change instance type or node count
```

---

### 1.3 — Init, Plan, Apply

```bash
cd infra/terraform

# Download providers and modules
terraform init

# Preview what will be created (no changes made)
terraform plan

# Create everything (~15 minutes)
terraform apply

# Type: yes
```

---

### 1.4 — Capture outputs (you need these for Ansible)

```bash
# Print all outputs
terraform output

# Get the ALB Controller IAM role ARN (copy this for Step 2)
terraform output alb_controller_role_arn

# Get the kubectl config command
terraform output configure_kubectl
```

---

### 1.5 — Configure kubectl

```bash
# Run the command from the output above, e.g.:
aws eks update-kubeconfig --region us-west-2 --name mega

# Verify cluster access
kubectl get nodes
kubectl get namespaces
```

---

## Step 2 — Ansible: Configure Cluster

Ansible runs locally and talks to the cluster via kubectl. All roles run in order
automatically via `site.yml`.

### What each role does

| Role | What it installs |
|---|---|
| `namespaces` | Creates `mega`, `prometheus`, `argocd` namespaces |
| `argocd` | Installs ArgoCD via Helm, prints initial admin password |
| `alb_controller` | Installs AWS Load Balancer Controller with IRSA |
| `prometheus` | Installs kube-prometheus-stack (Helm release name: `stable`) |
| `argocd_apps` | Creates ArgoCD Application → syncs `kubernetes/` folder |

---

### 2.1 — Run the full playbook

```bash
cd infra/ansible

ansible-playbook site.yml \
  -i inventory/localhost.yml \
  -e alb_controller_role_arn=<paste ARN from terraform output> \
  -e grafana_admin_password=YourSecurePassword123
```

---

### 2.2 — Run a single role (for re-runs or debugging)

```bash
# Only install prometheus
ansible-playbook site.yml \
  -i inventory/localhost.yml \
  --tags prometheus \
  -e grafana_admin_password=YourSecurePassword123

# Only create namespaces
ansible-playbook site.yml \
  -i inventory/localhost.yml \
  --tags namespaces

# Dry-run (check mode — no changes applied)
ansible-playbook site.yml \
  -i inventory/localhost.yml \
  --check \
  -e alb_controller_role_arn=arn:aws:iam::123456789:role/mega-alb-controller
```

> To use `--tags`, add a `tags:` line to each role entry in `site.yml`.
> Example: `- { role: prometheus, tags: prometheus }`

---

### 2.3 — Run with verbose output (useful for debugging)

```bash
ansible-playbook site.yml \
  -i inventory/localhost.yml \
  -e alb_controller_role_arn=<ARN> \
  -vv      # -v basic | -vv module output | -vvv connection debug
```

---

## Step 3 — Verify Everything

### ArgoCD

```bash
# Get ArgoCD LoadBalancer URL
kubectl get svc argocd-server -n argocd

# Get initial admin password (Ansible also prints this)
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open in browser: http://<EXTERNAL-IP>
# Login: admin / <password above>
```

### Grafana

```bash
# Get Grafana LoadBalancer URL
kubectl get svc stable-grafana -n prometheus

# Open in browser: http://<EXTERNAL-IP>
# Login: admin / YourSecurePassword123
```

### Prometheus

```bash
# Port-forward if you need direct Prometheus access
kubectl port-forward svc/stable-kube-prometheus-sta-prometheus \
  -n prometheus 9090:9090

# Open: http://localhost:9090
```

### Application pods (namespace: mega)

```bash
kubectl get pods -n mega
kubectl get svc  -n mega
kubectl get hpa  -n mega
kubectl get ingress -n mega
```

### ALB Ingress

```bash
# Check ALB controller logs
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  --tail=50

# Get ALB hostname
kubectl get ingress mega-ingress -n mega
```

---

## Destroying Everything

```bash
cd infra/terraform

# Preview what will be deleted
terraform plan -destroy

# Destroy all resources
terraform destroy
# Type: yes
```

> **Warning:** This deletes the EKS cluster, VPC, and all IAM roles.
> Make sure ArgoCD is not running important workloads before destroying.

---

## Troubleshooting

**`terraform init` fails — backend bucket not found**
→ Create the S3 bucket first (Step 1.1), then re-run `terraform init`.

**`kubectl get nodes` — no nodes / connection refused**
→ Re-run: `aws eks update-kubeconfig --region us-west-2 --name mega`

**Ansible — `kubernetes.core` module not found**
→ Run: `ansible-galaxy collection install -r ansible/requirements.yml`

**Ansible — `No module named kubernetes`**
→ Run: `pip3 install kubernetes`

**ALB controller not provisioning the ingress**
→ Check IAM role ARN was passed correctly and node group has internet access.
→ Check logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`

**ServiceMonitors not scraped by Prometheus**
→ Confirm Helm release name is `stable` (set in `group_vars/all.yml`).
→ ServiceMonitors in `kubernetes/service-monitors.yaml` already carry `release: stable`.

**ArgoCD app stuck OutOfSync**
→ `kubectl patch application microservices-platform -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'`
