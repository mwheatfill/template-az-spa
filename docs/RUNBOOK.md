# Runbook

Incident-specific playbooks. Run `npm run diagnose` first — most pages here build on
its output.

> Replace the `<app-specific>` callouts with details for your app once it diverges from the
> template defaults.

## App is down (users see errors / blank page / 500s)

1. **Diagnose first:**
   ```bash
   npm run diagnose
   ```
   It surfaces SWA status, last GH Actions deploy, App Insights failure count, app-setting
   names, Entra app health, availability test state, and current spend.

2. **App Insights** — open the link printed by diagnose. Look at the Failures blade for the
   last 24h. Group by operation name.

3. **SWA portal** — Static Web Apps → your app → Functions / Environments. Check the active
   deployment matches your latest `main` commit.

4. **GitHub Actions logs** — `gh run view --log` on the most recent run. Look for build
   errors, missing env vars, or `envsubst` failure on the tenant placeholder.

5. **<app-specific>**: list any external dependencies (PagerDuty API, Graph endpoints,
   internal services) and how to verify each is reachable.

## Auth is broken (everyone gets a redirect loop / 401)

1. **Entra app status** — `diagnose.sh` prints redirect URIs and secret expiry. Most common
   causes:
   - **Client secret expired** → re-run `./scripts/azure-deploy.sh`. The script mints a fresh
     secret and pushes it to SWA app settings; the script is idempotent.
   - **Redirect URI missing** for the SWA hostname (e.g. after creating a custom domain) →
     `azure-deploy.sh` adds the default hostname; add custom hostnames manually:
     ```bash
     az ad app update --id "$APP_ID" --web-redirect-uris \
       "$EXISTING_URI" "https://app.example.com/.auth/login/aad/callback"
     ```

2. **SWA app settings** — confirm `AAD_CLIENT_ID`, `AAD_CLIENT_SECRET`, `AAD_TENANT_ID` are
   present (`diagnose` prints names; portal shows values). If any are missing, re-run
   `azure-deploy.sh`.

3. **Tenant placeholder** — fetch the deployed `staticwebapp.config.json` from the SWA's
   `/staticwebapp.config.json` and confirm `__TENANT_ID__` was substituted for the real GUID.
   If the placeholder is still there, the GH Actions `envsubst` step failed — check that the
   `AAD_TENANT_ID` repository **variable** (not secret) is set on the repo.

## A Function is timing out (45s ceiling)

1. **App Insights → Performance → Dependencies.** Find the slowest upstream call. SWA managed
   Functions hard-cap at 45s; if you're routinely close, the work doesn't belong here.

2. **Check upstream API status pages.** PagerDuty, Microsoft 365, Graph — most "intermittent
   slow" issues trace back to a degraded dependency.

3. **Function logs** — SWA portal → your app → Functions → log stream. Or App Insights →
   Logs:
   ```
   traces | where timestamp > ago(1h) | where operation_Name == "<function-name>" | order by timestamp desc
   ```

4. **If the function legitimately needs >45s**: stop. This is a Tier 2 signal. Either
   pre-compute on a schedule and cache the result, or promote the app to Tier 2
   (`template-az-fullstack`).

## Rolling back a bad deploy

```bash
# Find the last good run
gh run list --workflow "Azure Static Web Apps CI/CD" --limit 10

# Re-run a previous successful build (this redeploys the artefact)
gh run rerun <run-id>
```

If you need to roll back the *code*: revert the bad commit on `main` (`git revert <sha> &&
git push`) — that's the cleanest path. Force-pushing main is not allowed under branch
protection and shouldn't be the answer.

## Rotating the Entra client secret

```bash
./scripts/azure-deploy.sh
```

The script is idempotent. Step 6 always mints a new client secret and pushes it to SWA app
settings. Old secrets remain on the app registration (not revoked) — clean them up via:

```bash
az ad app credential list --id "$APP_ID" --query "[].{name:displayName,id:keyId,end:endDateTime}" -o table
az ad app credential delete --id "$APP_ID" --key-id <KEY_ID>
```

## Cost spike

1. `diagnose.sh` prints the budget and recent usage. The budget alerts at 80% / 100% / 120%
   to `ALERT_EMAIL` — if you got the alert, that's why you're here.
2. **Cost Management in the portal** has the per-resource breakdown. SWA Free is $0; usual
   suspects on a Tier 1 app are App Insights ingestion (sampling is on by default but a
   chatty Function can still spike) and Log Analytics retention.
3. Reduce App Insights ingestion via `host.json` sampling settings (already conservative in
   the template) or by disabling fetch/ajax tracking in `src/lib/telemetry.ts`.

## <app-specific> sections to add as the app grows

Replace these placeholders with real playbooks when the relevant integrations land:

- **PagerDuty / on-call data is stale** — token rotation, schedule sync timing.
- **Graph rate-limited (429s)** — backoff settings, app-only vs delegated quotas.
- **Email send failing** — Mail.Send consent, shared-mailbox configuration.
- **A specific upstream API is down** — known status page URLs, fallback behaviour.
