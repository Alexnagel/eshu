# Managing Secrets

This document explains how to manage secrets that should not be committed to Git.

## ArgoCD Repository Access

To allow ArgoCD to pull from your private GitHub repository, you need to configure repository credentials.

### Option 1: Public Repository

If your repository is public, no additional configuration is needed. ArgoCD can pull directly.

### Option 2: GitHub App (Recommended for Private Repos)

GitHub Apps provide fine-grained permissions and better security than Personal Access Tokens.

1. **Create a GitHub App**:
   - Go to your GitHub account Settings → Developer settings → GitHub Apps
   - Or visit: https://github.com/settings/apps
   - Click "New GitHub App"
   
   **App Settings**:
   - **GitHub App name**: `argocd-eshu` (must be globally unique)
   - **Homepage URL**: `https://argoproj.github.io/cd/` (or your ArgoCD URL)
   - **Webhook**: Uncheck "Active" (not needed)
   - **Permissions** → Repository permissions:
     - **Contents**: Read-only (to read repository contents)
     - **Metadata**: Read-only (automatically selected)
   - **Where can this GitHub App be installed?**: Only on this account
   
   - Click "Create GitHub App"

2. **Generate a private key**:
   - On the app page, scroll down to "Private keys"
   - Click "Generate a private key"
   - Save the downloaded `.pem` file (e.g., `argocd-eshu.2026-01-16.private-key.pem`)

3. **Install the app on your repository**:
   - Go to the app page → "Install App"
   - Select your account
   - Choose "Only select repositories" and select `eshu`
   - Click "Install"
   - Note the **Installation ID** from the URL (e.g., `https://github.com/settings/installations/12345678` → ID is `12345678`)

4. **Get your App ID**:
   - Go back to the app settings page
   - Note the **App ID** (shown near the top of the page)

5. **Create the ArgoCD repository secret**:

```bash
# Set your values
APP_ID="123456"  # Your GitHub App ID
INSTALLATION_ID="12345678"  # Your Installation ID
PRIVATE_KEY_PATH="$HOME/Downloads/argocd-eshu.2026-01-16.private-key.pem"

# Create the secret
kubectl create secret generic eshu-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/anagelk1/eshu.git \
  --from-literal=githubAppID="$APP_ID" \
  --from-literal=githubAppInstallationID="$INSTALLATION_ID" \
  --from-file=githubAppPrivateKey="$PRIVATE_KEY_PATH" \
  --namespace=argocd

# Add the required label
kubectl label secret eshu-repo -n argocd argocd.argoproj.io/secret-type=repository
```

**Benefits of GitHub Apps**:
- ✅ Fine-grained repository access
- ✅ Higher API rate limits
- ✅ Better audit logs
- ✅ Can be scoped to specific repositories
- ✅ More secure than PATs

### Option 3: Private Repository with GitHub Personal Access Token

1. **Create a GitHub Personal Access Token (PAT)**:
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Or visit: https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Give it a name like "ArgoCD Access"
   - Select scopes: **repo** (full control of private repositories)
   - Click "Generate token"
   - **Copy the token immediately** (you won't see it again!)

2. **Create the ArgoCD repository secret**:

```bash
# Replace YOUR_GITHUB_PAT with your actual token
kubectl create secret generic eshu-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/anagelk1/eshu.git \
  --from-literal=username=anagelk1 \
  --from-literal=password=YOUR_GITHUB_PAT \
  --namespace=argocd

# Add the required label
kubectl label secret eshu-repo -n argocd argocd.argoproj.io/secret-type=repository
```

Or use the example file:

```bash
cp argocd-repo-secret.yaml.example argocd-repo-secret.yaml
# Edit and add your GitHub PAT
kubectl apply -f argocd-repo-secret.yaml
```

### Option 3: Using SSH Keys

1. **Generate an SSH key** (if you don't have one):

```bash
ssh-keygen -t ed25519 -C "argocd@eshu" -f ~/.ssh/argocd_eshu
```

2. **Add the public key to GitHub**:
   - Copy the public key: `cat ~/.ssh/argocd_eshu.pub`
   - Go to GitHub → Repository Settings → Deploy keys
   - Click "Add deploy key"
   - Paste the public key
   - Give it a name like "ArgoCD"
   - You can leave "Allow write access" unchecked (read-only is fine)

3. **Create the ArgoCD repository secret**:

```bash
kubectl create secret generic eshu-repo-ssh \
  --from-literal=type=git \
  --from-literal=url=git@github.com:anagelk1/eshu.git \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd_eshu \
  --namespace=argocd

kubectl label secret eshu-repo-ssh -n argocd argocd.argoproj.io/secret-type=repository
```

**Note**: If using SSH, update `app-of-apps.yaml` to use SSH URL: `git@github.com:anagelk1/eshu.git`

### Quick Comparison

| Method | Security | Setup Complexity | Best For |
|--------|----------|------------------|----------|
| Public Repo | N/A | Easiest | Public projects |
| GitHub App | ⭐⭐⭐⭐⭐ | Medium | **Recommended for production** |
| PAT | ⭐⭐⭐ | Easy | Quick testing, personal use |
| SSH Key | ⭐⭐⭐⭐ | Medium | Traditional approach |

### Verify Repository Connection

After creating the secret, verify in the ArgoCD UI:
1. Go to Settings → Repositories
2. You should see your repository listed with "Successful" connection status

Or via CLI:

```bash
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
```

## Pi-hole Admin Password

The Pi-hole admin password is stored in a Kubernetes secret that must be created manually.

### Create the Secret

```bash
# Generate a secure password
PASSWORD=$(openssl rand -base64 32)
echo "Your Pi-hole password: $PASSWORD"

# Create the secret in the cluster
kubectl create secret generic pihole-password \
  --from-literal=password="$PASSWORD" \
  --namespace=pihole \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or use a specific password:

```bash
kubectl create secret generic pihole-password \
  --from-literal=password="YourSecurePassword" \
  --namespace=pihole
```

### Using the Example Template

Alternatively, copy the example and modify it locally:

```bash
cp applications/pihole/secret.yaml.example applications/pihole/secret.yaml
# Edit the password in secret.yaml
kubectl apply -f applications/pihole/secret.yaml
```

**Note:** The `secret.yaml` file is gitignored and won't be committed to your repository.

## Future Secrets

For additional secrets, follow the same pattern:
1. Create a `.example` file in the repository
2. The actual secret file is gitignored
3. Create secrets manually in the cluster or use a secrets management solution

## Advanced Options

For production environments, consider:

### 1. Sealed Secrets
Encrypt secrets that can be safely stored in Git and decrypted only in the cluster.

```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Encrypt a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

### 2. External Secrets Operator
Sync secrets from external secret stores (AWS Secrets Manager, Vault, etc.).

### 3. SOPS + Age
Encrypt files in Git using Mozilla SOPS with age encryption.

```bash
# Install age and sops
brew install age sops

# Generate an age key
age-keygen -o key.txt

# Encrypt the secret
sops --encrypt --age $(cat key.txt | grep public | cut -d: -f2) secret.yaml > secret.enc.yaml
```
