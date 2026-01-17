# ArgoCD Bootstrap with App-of-Apps Pattern

This repository contains the bootstrap configuration for ArgoCD with self-management capabilities.

## Structure

```
.
├── app-of-apps.yaml         # Root application (manages all other apps)
└── applications/
    ├── argocd/
    │   └── application.yaml # ArgoCD self-management
    ├── metallb/
    │   ├── application.yaml # MetalLB deployment
    │   └── config.yaml      # MetalLB IP pool configuration
    └── pihole/
        ├── application.yaml # Pi-hole deployment
        └── secret.yaml      # Pi-hole admin password
```

## Prerequisites

- Clean k3s cluster
- kubectl configured to access your cluster
- Git repository (push this code to your repo)

## Initial Setup

### 1. Update Configuration

Before deploying, update these files:

**app-of-apps.yaml**:
- Update `repoURL` with your Git repository URL
- Update `targetRevision` if using a specific branch

**applications/metallb/config.yaml**:
- Update the IP address range to match your local network (e.g., `192.168.1.240-192.168.1.250`)

**Pi-hole Admin Password**:
- See [SECRETS.md](SECRETS.md) for instructions on creating the Pi-hole password secret

### 2. Install ArgoCD (First Time Only)

```bash
# Install ArgoCD using kubectl
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 3. Create Secrets

**ArgoCD Repository Access** (only needed for private repositories):

See [SECRETS.md](SECRETS.md) for detailed instructions. 

**Recommended: GitHub App** (most secure):

```bash
# After creating the GitHub App and downloading the private key
kubectl create secret generic eshu-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/anagelk1/eshu.git \
  --from-literal=githubAppID="YOUR_APP_ID" \
  --from-literal=githubAppInstallationID="YOUR_INSTALLATION_ID" \
  --from-file=githubAppPrivateKey="path/to/private-key.pem" \
  --namespace=argocd && \
kubectl label secret eshu-repo -n argocd argocd.argoproj.io/secret-type=repository
```

**Alternative: Personal Access Token** (simpler for testing):

```bash
# Create GitHub Personal Access Token first at https://github.com/settings/tokens
kubectl create secret generic eshu-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/anagelk1/eshu.git \
  --from-literal=username=anagelk1 \
  --from-literal=password=YOUR_GITHUB_PAT \
  --namespace=argocd && \
kubectl label secret eshu-repo -n argocd argocd.argoproj.io/secret-type=repository
```

**Pi-hole Admin Password**:

Create the Pi-hole admin password secret (see [SECRETS.md](SECRETS.md) for details):

```bash
# Create the pihole namespace first
kubectl create namespace pihole

# Create the secret with a secure password
kubectl create secret generic pihole-password \
  --from-literal=password="$(openssl rand -base64 32)" \
  --namespace=pihole
```

### 4. Push to Git Repository

```bash
git add app-of-apps.yaml applications/ .gitignore SECRETS.md
git commit -m "Add ArgoCD bootstrap configuration"
git push
```

### 5. Deploy the App-of-Apps

```bash
# Apply the root app-of-apps application
kubectl apply -f app-of-apps.yaml
```

This will trigger ArgoCD to:
1. Take over its own management (ArgoCD becomes self-managed)
2. Deploy MetalLB (sync-wave: 1)
3. Configure MetalLB IP pool (sync-wave: 2)
4. Deploy Pi-hole (sync-wave: 3)

### 6. Access ArgoCD UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access the UI (temporary)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Once MetalLB is running, ArgoCD will get a LoadBalancer IP. Check with:
```bash
kubectl get svc -n argocd argocd-server
```

Access at: `http://<EXTERNAL-IP>` (username: `admin`, password: from step above)

### 7. Access Pi-hole

Once Pi-hole is deployed, get its LoadBalancer IP:
```bash
kubectl get svc -n pihole pihole-web
```

Access the Pi-hole admin interface at: `http://<EXTERNAL-IP>/admin`

## Sync Waves

The deployment uses sync waves to ensure proper ordering:
- **Wave 1**: MetalLB deployment
- **Wave 2**: MetalLB configuration & Pi-hole secrets
- **Wave 3**: Pi-hole deployment

## Post-Deployment

### Configure DNS

To use Pi-hole as your DNS server:
1. Access Pi-hole admin interface
2. Configure your router to use the Pi-hole IP as the DNS server, OR
3. Configure individual devices to use Pi-hole as their DNS server

### Add Custom DNS Records

You can add local DNS records in Pi-hole to access services by name:
1. Go to Local DNS → DNS Records
2. Add entries for your services (e.g., `argocd.local`, `pihole.local`)

## Managing Applications

All applications are now managed by ArgoCD. To add new applications:

1. Create a new directory in `applications/`
2. Add an `application.yaml` file
3. Commit and push to Git
4. ArgoCD will automatically detect and deploy it

## Troubleshooting

### Check ArgoCD Application Status
```bash
kubectl get applications -n argocd
```

### Check Application Details
```bash
kubectl describe application <app-name> -n argocd
```

### Check Sync Status in UI
Access the ArgoCD UI and check the application sync status and health.

### MetalLB Not Assigning IPs
```bash
# Check MetalLB logs
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller

# Verify IP pool configuration
kubectl get ipaddresspool -n metallb-system
```

## Cleanup

To remove everything:
```bash
kubectl delete application app-of-apps -n argocd
# Wait for all apps to be cleaned up, then:
kubectl delete namespace argocd metallb-system pihole
```
