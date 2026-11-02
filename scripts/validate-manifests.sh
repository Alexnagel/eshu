#!/usr/bin/env bash
# Renders every Argo CD Application's Helm chart at its pinned version with
# the values files from this repo, then schema-validates the output with
# kubeconform. Also validates the raw manifests in deployments/.
#
# This is the guard for Renovate chart bumps: a values file that is
# incompatible with the new chart version fails here, before Argo sees it.
#
# Usage: validate-manifests.sh [repo-dir] [render-dir]
#   repo-dir    checkout to process (default: pull-request)
#   render-dir  if set, also write each rendered chart to <render-dir>/<app>__<chart>.yaml
#               so two checkouts can be diffed (see diff-manifests.sh)
# Env:
#   RENDER_ONLY=1  skip kubeconform and never fail on a render error (used for
#                  the base branch, where only the rendered output matters)
set -uo pipefail

REPO_DIR="${1:-pull-request}"
RENDER_DIR="${2:-}"
RENDER_ONLY="${RENDER_ONLY:-}"

CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
# RenovateJob is skipped: the CRDs-catalog schema for it is older than the
# operator's actual CRD (missing githubAppReference etc.)
KUBECONFORM_ARGS=(-strict -ignore-missing-schemas -summary -skip RenovateJob
  -schema-location default -schema-location "$CRD_SCHEMAS")
FAIL=0

command -v helm >/dev/null || { echo "helm not found" >&2; exit 1; }
command -v yq >/dev/null || { echo "yq not found" >&2; exit 1; }
[ -n "$RENDER_ONLY" ] || command -v kubeconform >/dev/null \
  || { echo "kubeconform not found" >&2; exit 1; }

if [ -n "$RENDER_DIR" ]; then
  mkdir -p "$RENDER_DIR"
  RENDER_DIR="$(cd "$RENDER_DIR" && pwd)"
fi

pushd "$REPO_DIR" >/dev/null
# ── 1. Render every helm-chart source in applications/*/application.yaml ──
for app in applications/*/application.yaml app-of-apps.yaml; do
  name=$(yq -r '.metadata.name' "$app")
  ns=$(yq -r '.spec.destination.namespace // "default"' "$app")

  # Collect chart sources from both single-source and multi-source specs
  charts=$(yq -o=json -I0 '[.spec.source, .spec.sources[]?] | .[] | select(. != null and has("chart"))' "$app")
  [ -z "$charts" ] && continue

  while IFS= read -r src; do
    repo=$(echo "$src" | yq -r '.repoURL')
    chart=$(echo "$src" | yq -r '.chart')
    ver=$(echo "$src" | yq -r '.targetRevision')
    release=$(echo "$src" | yq -r ".helm.releaseName // \"$name\"")

    vfargs=()
    for vf in $(echo "$src" | yq -r '.helm.valueFiles[]? // ""'); do
      vfargs+=(-f "${vf#\$values/}")   # $values/<path> → repo-relative path
    done

    echo "──── $name: $chart@$ver"
    # kubeconform ignores files without a .yaml extension
    out="$(mktemp).yaml"
    if ! helm template "$release" "$chart" --repo "$repo" --version "$ver" \
        --namespace "$ns" ${vfargs[@]+"${vfargs[@]}"} >"$out" 2>"$out.err"; then
      echo "::error file=$app::helm render failed for $name ($chart@$ver)"
      cat "$out.err"
      [ -n "$RENDER_ONLY" ] || FAIL=1
      continue
    fi
    [ -z "$RENDER_DIR" ] || cp "$out" "$RENDER_DIR/${name}__${chart}.yaml"
    [ -n "$RENDER_ONLY" ] || kubeconform "${KUBECONFORM_ARGS[@]}" "$out" || FAIL=1
  done <<< "$charts"
done

# ── 2. Validate raw manifests (Applications themselves + deployments/) ──
if [ -z "$RENDER_ONLY" ]; then
  echo "──── raw manifests"
  find applications app-of-apps.yaml deployments -name '*.yaml' \
      ! -name 'values.yaml' -type f 2>/dev/null \
    | xargs kubeconform "${KUBECONFORM_ARGS[@]}" || FAIL=1
fi

exit $FAIL
