#!/usr/bin/env bash
# One-shot, idempotent Azure Static Web Apps + Entra ID + observability bootstrap.
#
# Required env vars:
#   SUB                 Azure subscription id (GUID)
#   TENANT              Entra tenant id (GUID)
#   RG                  Resource group name
#   LOC                 Region (westus2, eastus2, centralus, eastasia, westeurope)
#   SWA_NAME            Static Web App name
#   GH_REPO             owner/repo of the GitHub repo
#   APP_DISPLAY_NAME    Entra app registration display name
#   ALERT_EMAIL         Email for availability + budget alerts
#
# Optional:
#   MONTHLY_BUDGET_USD  RG monthly budget cap (default: 20)
#   GRAPH_SCOPES        Comma-separated Graph scopes to print admin-consent URL for
#                       (e.g. "User.Read.All,Mail.Send"). Empty = skip.
#
# Prereqs: az CLI, gh CLI, both logged in. Re-run safely: every step is idempotent.

set -euo pipefail

: "${SUB:?SUB is required}"
: "${TENANT:?TENANT is required}"
: "${RG:?RG is required}"
: "${LOC:?LOC is required}"
: "${SWA_NAME:?SWA_NAME is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${APP_DISPLAY_NAME:?APP_DISPLAY_NAME is required}"
: "${ALERT_EMAIL:?ALERT_EMAIL is required}"

MONTHLY_BUDGET_USD="${MONTHLY_BUDGET_USD:-20}"
GRAPH_SCOPES="${GRAPH_SCOPES:-}"

AI_NAME="${SWA_NAME}-ai"
LAW_NAME="${SWA_NAME}-law"
ACTION_GROUP_NAME="${SWA_NAME}-alerts"
ACTION_GROUP_SHORT="${SWA_NAME:0:12}"          # action group short name <= 12 chars
AVAILABILITY_TEST_NAME="${SWA_NAME}-ping"
BUDGET_NAME="${RG}-budget"

step() { printf "\n▶ %s\n" "$*"; }

step "Using subscription $SUB"
az account set --subscription "$SUB"

# 1. Resource group ----------------------------------------------------------
step "Ensuring resource group $RG in $LOC (idempotent)"
az group create --name "$RG" --location "$LOC" --output none

# 2. Static Web App (Free) ---------------------------------------------------
step "Ensuring SWA $SWA_NAME (Free tier)"
if ! az staticwebapp show --name "$SWA_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  az staticwebapp create \
    --name "$SWA_NAME" \
    --resource-group "$RG" \
    --location "$LOC" \
    --sku Free \
    --output none
  echo "  created $SWA_NAME"
else
  echo "  reusing existing $SWA_NAME"
fi

SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --resource-group "$RG" --query defaultHostname -o tsv)
SWA_URL="https://$SWA_HOSTNAME"
echo "  hostname: $SWA_URL"

# 3. Deployment token -> GH secret -------------------------------------------
step "Pushing SWA deployment token to GitHub as AZURE_STATIC_WEB_APPS_API_TOKEN"
SWA_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --resource-group "$RG" --query properties.apiKey -o tsv)
if [ -z "$SWA_TOKEN" ]; then
  echo "!! No deployment token returned." >&2
  exit 1
fi
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --repo "$GH_REPO" --body "$SWA_TOKEN" >/dev/null

# 4. Entra app registration --------------------------------------------------
step "Ensuring Entra app registration '$APP_DISPLAY_NAME'"
REDIRECT_URI="$SWA_URL/.auth/login/aad/callback"
APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [ -z "${APP_ID:-}" ] || [ "$APP_ID" = "null" ]; then
  APP_ID=$(az ad app create \
    --display-name "$APP_DISPLAY_NAME" \
    --sign-in-audience AzureADMyOrg \
    --web-redirect-uris "$REDIRECT_URI" \
    --query appId -o tsv)
  echo "  created app id $APP_ID"
else
  echo "  reusing app id $APP_ID"
  # 5. Ensure redirect URI present (idempotent merge)
  EXISTING=$(az ad app show --id "$APP_ID" --query "web.redirectUris" -o tsv | tr '\n' ' ')
  if ! echo "$EXISTING" | grep -q "$REDIRECT_URI"; then
    MERGED="$EXISTING $REDIRECT_URI"
    # shellcheck disable=SC2086
    az ad app update --id "$APP_ID" --web-redirect-uris $MERGED --output none
    echo "  added redirect URI $REDIRECT_URI"
  fi
fi

# Service principal in tenant (required for SWA EasyAuth)
if ! az ad sp show --id "$APP_ID" >/dev/null 2>&1; then
  az ad sp create --id "$APP_ID" --output none
fi

# 6. Client secret ------------------------------------------------------------
step "Minting client secret and pushing to SWA app settings"
CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --display-name "swa-auth" --years 2 --query password -o tsv)

az staticwebapp appsettings set \
  --name "$SWA_NAME" \
  --resource-group "$RG" \
  --setting-names \
    "AAD_CLIENT_ID=$APP_ID" \
    "AAD_CLIENT_SECRET=$CLIENT_SECRET" \
    "AAD_TENANT_ID=$TENANT" \
  --output none

# 7-8. Push tenant + client id as GH variables (not secrets) -----------------
step "Pushing AAD_CLIENT_ID and AAD_TENANT_ID as GitHub repository variables"
gh variable set AAD_CLIENT_ID --repo "$GH_REPO" --body "$APP_ID" >/dev/null
gh variable set AAD_TENANT_ID --repo "$GH_REPO" --body "$TENANT" >/dev/null

# 9. Application Insights (workspace-based) ----------------------------------
step "Ensuring Log Analytics workspace $LAW_NAME"
if ! az monitor log-analytics workspace show -g "$RG" -n "$LAW_NAME" >/dev/null 2>&1; then
  az monitor log-analytics workspace create \
    --resource-group "$RG" \
    --workspace-name "$LAW_NAME" \
    --location "$LOC" \
    --output none
fi
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW_NAME" --query id -o tsv)

step "Ensuring Application Insights $AI_NAME (workspace-based)"
if ! az monitor app-insights component show --app "$AI_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  az monitor app-insights component create \
    --app "$AI_NAME" \
    --location "$LOC" \
    --resource-group "$RG" \
    --workspace "$LAW_ID" \
    --output none
fi
AI_CONN=$(az monitor app-insights component show --app "$AI_NAME" --resource-group "$RG" --query connectionString -o tsv)
AI_ID=$(az monitor app-insights component show --app "$AI_NAME" --resource-group "$RG" --query id -o tsv)

az staticwebapp appsettings set \
  --name "$SWA_NAME" \
  --resource-group "$RG" \
  --setting-names \
    "APPINSIGHTS_CONNECTION_STRING=$AI_CONN" \
    "VITE_APPINSIGHTS_CONNECTION_STRING=$AI_CONN" \
  --output none

# 10. Action group ------------------------------------------------------------
step "Ensuring action group $ACTION_GROUP_NAME (email -> $ALERT_EMAIL)"
if ! az monitor action-group show --resource-group "$RG" --name "$ACTION_GROUP_NAME" >/dev/null 2>&1; then
  az monitor action-group create \
    --resource-group "$RG" \
    --name "$ACTION_GROUP_NAME" \
    --short-name "$ACTION_GROUP_SHORT" \
    --action email "$ACTION_GROUP_SHORT-em" "$ALERT_EMAIL" \
    --output none
fi
ACTION_GROUP_ID=$(az monitor action-group show --resource-group "$RG" --name "$ACTION_GROUP_NAME" --query id -o tsv)

# 11. Availability test + alert ----------------------------------------------
step "Ensuring availability test $AVAILABILITY_TEST_NAME (5min, 5 regions)"
# az monitor app-insights web-test/availability commands churn between versions.
# Use ARM template via az deployment to keep this stable.
TEST_GUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
WEBTEST_ARM=$(mktemp)
cat >"$WEBTEST_ARM" <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "aiName": { "type": "string" },
    "testName": { "type": "string" },
    "url": { "type": "string" },
    "location": { "type": "string" },
    "actionGroupId": { "type": "string" }
  },
  "variables": {
    "aiResourceId": "[resourceId('Microsoft.Insights/components', parameters('aiName'))]"
  },
  "resources": [
    {
      "type": "Microsoft.Insights/webtests",
      "apiVersion": "2022-06-15",
      "name": "[parameters('testName')]",
      "location": "[parameters('location')]",
      "tags": {
        "[concat('hidden-link:', variables('aiResourceId'))]": "Resource"
      },
      "properties": {
        "Name": "[parameters('testName')]",
        "SyntheticMonitorId": "[parameters('testName')]",
        "Description": "Availability ping for SWA",
        "Enabled": true,
        "Frequency": 300,
        "Timeout": 30,
        "Kind": "ping",
        "RetryEnabled": true,
        "Locations": [
          { "Id": "us-ca-sjc-azr" },
          { "Id": "us-tx-sn1-azr" },
          { "Id": "us-il-ch1-azr" },
          { "Id": "us-va-ash-azr" },
          { "Id": "us-fl-mia-edge" }
        ],
        "Configuration": {
          "WebTest": "[concat('<WebTest Name=\"', parameters('testName'), '\" Enabled=\"True\" Timeout=\"30\" StopOnFault=\"true\"><Items><Request Method=\"GET\" Url=\"', parameters('url'), '\" ExpectedHttpStatusCode=\"200\" FollowRedirects=\"True\" /></Items></WebTest>')]"
        }
      }
    },
    {
      "type": "Microsoft.Insights/metricAlerts",
      "apiVersion": "2018-03-01",
      "name": "[concat(parameters('testName'), '-alert')]",
      "location": "global",
      "dependsOn": [
        "[resourceId('Microsoft.Insights/webtests', parameters('testName'))]"
      ],
      "properties": {
        "description": "Alert when SWA availability test fails in 3+ locations",
        "severity": 2,
        "enabled": true,
        "scopes": [
          "[resourceId('Microsoft.Insights/webtests', parameters('testName'))]",
          "[variables('aiResourceId')]"
        ],
        "evaluationFrequency": "PT1M",
        "windowSize": "PT5M",
        "criteria": {
          "odata.type": "Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria",
          "webTestId": "[resourceId('Microsoft.Insights/webtests', parameters('testName'))]",
          "componentId": "[variables('aiResourceId')]",
          "failedLocationCount": 3
        },
        "actions": [
          { "actionGroupId": "[parameters('actionGroupId')]" }
        ]
      }
    }
  ]
}
JSON

az deployment group create \
  --resource-group "$RG" \
  --name "webtest-${TEST_GUID:0:8}" \
  --template-file "$WEBTEST_ARM" \
  --parameters \
    "aiName=$AI_NAME" \
    "testName=$AVAILABILITY_TEST_NAME" \
    "url=$SWA_URL" \
    "location=$LOC" \
    "actionGroupId=$ACTION_GROUP_ID" \
  --output none
rm -f "$WEBTEST_ARM"

# 12. Monthly budget on the RG -----------------------------------------------
step "Ensuring monthly budget on $RG (\$$MONTHLY_BUDGET_USD/mo)"
START_DATE=$(date -u +"%Y-%m-01")
END_DATE=$(date -u -v+5y +"%Y-%m-01" 2>/dev/null || date -u -d "+5 years" +"%Y-%m-01")

if ! az consumption budget show --budget-name "$BUDGET_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  az consumption budget create \
    --budget-name "$BUDGET_NAME" \
    --amount "$MONTHLY_BUDGET_USD" \
    --category cost \
    --time-grain monthly \
    --start-date "$START_DATE" \
    --end-date "$END_DATE" \
    --resource-group "$RG" \
    --notifications "Actual_GreaterThan_80=enabled=true threshold=80 operator=GreaterThan contactEmails=$ALERT_EMAIL thresholdType=Actual" \
                    "Actual_GreaterThan_100=enabled=true threshold=100 operator=GreaterThan contactEmails=$ALERT_EMAIL thresholdType=Actual" \
                    "Forecasted_GreaterThan_120=enabled=true threshold=120 operator=GreaterThan contactEmails=$ALERT_EMAIL thresholdType=Forecasted" \
    --output none 2>/dev/null \
  || echo "  (budget create syntax varies by az CLI version; create manually if this errored)"
else
  echo "  reusing existing budget $BUDGET_NAME"
fi

# 13. Graph admin consent URL ------------------------------------------------
if [ -n "$GRAPH_SCOPES" ]; then
  step "Graph admin consent required"
  CONSENT_URL="https://login.microsoftonline.com/$TENANT/adminconsent?client_id=$APP_ID"
  echo "  Scopes declared: $GRAPH_SCOPES"
  echo "  A Global Admin must grant tenant-wide consent at:"
  echo "    $CONSENT_URL"
fi

# 14. Final summary ----------------------------------------------------------
AI_PORTAL_URL="https://portal.azure.com/#@$TENANT/resource$AI_ID/overview"
cat <<EOF

✅ Bootstrap complete.

  Static Web App  : $SWA_URL
  Entra app id    : $APP_ID
  Redirect URI    : $REDIRECT_URI
  App Insights    : $AI_PORTAL_URL
  Availability    : $AVAILABILITY_TEST_NAME (5min, alert -> $ALERT_EMAIL)
  Monthly budget  : \$$MONTHLY_BUDGET_USD on RG $RG (alerts -> $ALERT_EMAIL)

Next steps:
  1. Commit and push:    git add -A && git commit -m "wire up SWA" && git push
  2. Watch the build:    gh run watch
  3. Visit $SWA_URL — you'll be redirected to Entra to sign in.
  4. Set branch protection on main (Settings -> Branches) to require both
     "Azure Static Web Apps CI/CD" and "CI" checks before merge.

Re-run this script any time. Steps that already exist are skipped or merged;
the client secret is regenerated and pushed to SWA app settings.
EOF
