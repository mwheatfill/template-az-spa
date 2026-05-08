#!/usr/bin/env bash
# Read-only diagnostics for a Tier 1 SPA deployment.
# Surfaces what's running, what's failing, and where to look next.
#
# Required env vars (same set as azure-deploy.sh):
#   SUB, RG, SWA_NAME, GH_REPO, APP_DISPLAY_NAME, ALERT_EMAIL (informational)
#
# Optional: TENANT (for portal links)

set -uo pipefail

: "${SUB:?SUB is required}"
: "${RG:?RG is required}"
: "${SWA_NAME:?SWA_NAME is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${APP_DISPLAY_NAME:?APP_DISPLAY_NAME is required}"

TENANT="${TENANT:-}"
AI_NAME="${SWA_NAME}-ai"
AVAILABILITY_TEST_NAME="${SWA_NAME}-ping"
BUDGET_NAME="${RG}-budget"

hr() { printf "\n%s\n" "────────────────────────────────────────────────────────"; }
title() { printf "\n■ %s" "$*"; hr; }

az account set --subscription "$SUB" 2>/dev/null || true

title "Resource group"
az group show --name "$RG" --query "{name:name, location:location, provisioningState:properties.provisioningState}" -o table 2>/dev/null \
  || echo "  ⚠ resource group $RG not found"

title "Static Web App"
az staticwebapp show --name "$SWA_NAME" --resource-group "$RG" \
  --query "{name:name, status:repositoryUrl == null && 'standalone' || 'wired', sku:sku.name, hostname:defaultHostname, customDomains:customDomains}" \
  -o table 2>/dev/null \
  || echo "  ⚠ SWA $SWA_NAME not found"

SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --resource-group "$RG" --query defaultHostname -o tsv 2>/dev/null || echo "")
[ -n "$SWA_HOSTNAME" ] && echo "  URL: https://$SWA_HOSTNAME"

title "Last GitHub Actions deploy"
gh run list --repo "$GH_REPO" --workflow "Azure Static Web Apps CI/CD" --limit 3 \
  --json databaseId,headBranch,conclusion,createdAt,headSha,event \
  --template '{{range .}}{{printf "  %-12s %-9s %s  %s  %.7s  %s\n" .event (.conclusion | default "running") .createdAt .headBranch .headSha (printf "%v" .databaseId)}}{{end}}' 2>/dev/null \
  || echo "  ⚠ gh CLI not authenticated or repo not found"

title "App Insights"
AI_ID=$(az monitor app-insights component show --app "$AI_NAME" --resource-group "$RG" --query id -o tsv 2>/dev/null || echo "")
if [ -n "$AI_ID" ]; then
  echo "  Resource ID: $AI_ID"
  if [ -n "$TENANT" ]; then
    echo "  Portal:      https://portal.azure.com/#@$TENANT/resource$AI_ID/overview"
  fi
  echo
  echo "  Failures in the last 24h:"
  az monitor app-insights query \
    --app "$AI_NAME" -g "$RG" \
    --analytics-query "union requests, exceptions | where timestamp > ago(24h) | where success == false or itemType == 'exception' | summarize count() by itemType" \
    --query "tables[0].rows" -o tsv 2>/dev/null \
    | sed 's/^/    /' \
    || echo "    (no data or query failed)"
else
  echo "  ⚠ App Insights resource $AI_NAME not found"
fi

title "SWA app settings (names only — values redacted)"
az staticwebapp appsettings list --name "$SWA_NAME" --resource-group "$RG" \
  --query "properties | keys(@)" -o tsv 2>/dev/null \
  | sed 's/^/  /' \
  || echo "  ⚠ unable to read app settings"

title "Entra app registration"
APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")
if [ -n "$APP_ID" ]; then
  echo "  Display name : $APP_DISPLAY_NAME"
  echo "  App ID       : $APP_ID"
  echo "  Redirect URIs:"
  az ad app show --id "$APP_ID" --query "web.redirectUris" -o tsv 2>/dev/null | sed 's/^/    /'
  echo "  Secrets:"
  az ad app credential list --id "$APP_ID" \
    --query "[].{name:displayName, endDateTime:endDateTime}" -o table 2>/dev/null \
    | sed 's/^/    /'
else
  echo "  ⚠ no app registration matching '$APP_DISPLAY_NAME'"
fi

title "Availability test + alert"
az monitor app-insights web-test list --resource-group "$RG" \
  --query "[?name=='$AVAILABILITY_TEST_NAME'].{name:name, enabled:enabled, frequency:frequency, kind:kind}" \
  -o table 2>/dev/null \
  | sed 's/^/  /' \
  || echo "  ⚠ unable to read web tests"

az monitor metrics alert list --resource-group "$RG" \
  --query "[?contains(name, '$AVAILABILITY_TEST_NAME')].{name:name, enabled:enabled, severity:severity}" \
  -o table 2>/dev/null \
  | sed 's/^/  /'

title "Current month spend vs budget"
BUDGET_AMOUNT=$(az consumption budget show --budget-name "$BUDGET_NAME" --resource-group "$RG" --query amount -o tsv 2>/dev/null || echo "")
if [ -n "$BUDGET_AMOUNT" ]; then
  echo "  Budget:        \$$BUDGET_AMOUNT/mo (RG: $RG)"
fi
USAGE=$(az consumption usage list --start-date "$(date -u +%Y-%m-01)" --end-date "$(date -u +%Y-%m-%d)" \
  --query "[?contains(instanceId, '$RG')] | [0:5].{date:usageStart, cost:pretaxCost, currency:currency}" \
  -o table 2>/dev/null || echo "")
if [ -n "$USAGE" ]; then
  echo "$USAGE" | sed 's/^/  /'
else
  echo "  (consumption data takes 8-24h to populate; check Cost Management in the portal)"
fi

hr
echo "Done. For deeper investigation see docs/RUNBOOK.md."
