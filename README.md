# eshu — GitOps homelab on k3s

This repository is the single source of truth for a k3s homelab, managed by
Argo CD using the **app-of-apps** pattern. Argo CD manages itself, and one root
Application deploys everything else.

## Structure

```
.
├── app-of-apps.yaml          # Root Application — deploys every applications/*/application.yaml
├── renovate.json5            # Renovate config (dependency update PRs)
├── SECRETS.md                # How to create the secrets that must not live in Git
├── applications/             # One Argo CD Application per component (the "what")
│   ├── argocd/               #   Argo CD (self-managed)
│   ├── cloudflared/          #   Cloudflare Tunnel (public access to selected services)
│   ├── metallb/              #   MetalLB (bare-metal LoadBalancer)
│   ├── metallb-config/       #   MetalLB IP pool + L2Advertisement
│   ├── nvidia-device-plugin/ #   NVIDIA device plugin (GPU scheduling)
│   ├── traefik/              #   Traefik ingress + ACME/Cloudflare TLS
│   ├── immich/               #   Immich photo library (+ dedicated Postgres)
│   ├── pihole/               #   Pi-hole DNS
│   ├── plex/                 #   Plex Media Server (GPU transcoding)
│   ├── sonarr/               #   Sonarr (TV)          → media namespace
│   ├── radarr/               #   Radarr (movies)      → media namespace
│   ├── seerr/                #   Seerr (requests)     → media namespace
│   ├── sabnzbd/              #   SABnzbd (usenet)     → media namespace
│   └── renovate/             #   Renovate operator
└── deployments/              # Helm values + extra manifests per component (the "how")
    └── <app>/
        ├── values.yaml       #   Helm chart values
        └── ingressroute.yaml #   Traefik IngressRoutes / Middlewares (where applicable)
```

The split is deliberate: `applications/` holds the Argo CD `Application` objects
(which chart, which version), while `deployments/` holds the per-app
configuration those Applications point at via a multi-source `$values` reference.

## How it fits together

- **app-of-apps** (`app-of-apps.yaml`) watches `applications/**/application.yaml`
  and creates one Argo CD `Application` per directory.
- Each `Application` has `syncPolicy.automated` with `prune` + `selfHeal`, so the
  cluster continuously converges to what is in Git on the `main` branch.
- **Sync waves** order the rollout:
  - **Wave 1**: MetalLB, NVIDIA device plugin, Renovate
  - **Wave 2**: MetalLB IP pool config
  - **Wave 3**: Traefik
  - **Wave 4**: Pi-hole, Plex
  Argo CD is configured (see `deployments/argocd/values.yaml`) to consider child
  Application health, so a wave waits for the previous one to become Healthy.
- **Traefik** terminates TLS using a Cloudflare DNS-01 ACME resolver and
  redirects all plain HTTP to HTTPS at the `web` entrypoint, so individual
  services only declare a `websecure` `IngressRoute`.

Services are reachable at `https://<app>.nagelkerke.net` (argocd, pihole,
traefik, plex, renovate), resolved by Pi-hole's custom DNS to the Traefik
LoadBalancer IP.

## Prerequisites

- A running k3s cluster with `kubectl` access
- This repo pushed to `https://github.com/Alexnagel/eshu` (`main` branch)
- An NVIDIA GPU + drivers on the node named `eshu` (for Plex transcoding)

## Bootstrap

### 1. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2. Create the required secrets

These are intentionally **not** in Git. See [SECRETS.md](SECRETS.md) for details.

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `eshu-repo` | `argocd` | Repo access (only if the repo is private) |
| `cloudflare-api-token` | `traefik` | Cloudflare DNS-01 token for ACME TLS |
| `pihole-password` | `pihole` | Pi-hole admin password |
| `renovate-github-app` | `renovate` | GitHub App creds for the Renovate operator |
| `cloudflared-token` | `cloudflared` | Cloudflare Tunnel connector token (public access) |
| `immich-db` | `immich` | Immich Postgres password (same as compose `.env`) |

### 3. Deploy the root Application

```bash
kubectl apply -f app-of-apps.yaml
```

Argo CD takes over management of itself and rolls out every component in
sync-wave order.

### 4. Access the Argo CD UI

```bash
# Initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Once Traefik and Pi-hole are up, browse to `https://argocd.nagelkerke.net`
(user `admin`).

## Dependency updates

[Renovate](https://docs.renovatebot.com/) runs in-cluster via the renovate
operator and opens grouped update PRs on weekends (`renovate.json5`). It tracks
Argo CD chart versions, Helm values, container image tags, and GitHub Actions.
Major updates are never auto-merged. The Dependency Dashboard issue tracks
everything pending.

## CI

`.github/workflows/qualify.yaml` runs on every PR and push to `main`:
- **super-linter** validates YAML and GitHub Actions workflows
- the Renovate config is validated whenever `renovate.json5` changes

## Managing applications

To add a component:

1. Create `applications/<name>/application.yaml` (copy an existing one).
2. Add `deployments/<name>/values.yaml` (and `ingressroute.yaml` if it needs
   ingress).
3. Commit and push to `main` — Argo CD detects and deploys it automatically.

## Troubleshooting

```bash
# Application status
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# MetalLB not assigning IPs
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller
kubectl get ipaddresspool -n metallb-system
```

## Cleanup

```bash
kubectl delete application app-of-apps -n argocd
# wait for children to be pruned, then:
kubectl delete namespace argocd metallb-system traefik pihole plex renovate
```
