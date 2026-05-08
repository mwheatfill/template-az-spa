import { ClientSecretCredential } from "@azure/identity";
import { Client } from "@microsoft/microsoft-graph-client";

const SCOPE = "https://graph.microsoft.com/.default";

let cached: { token: string; expiresOn: number } | null = null;
let credential: ClientSecretCredential | null = null;

function getCredential(): ClientSecretCredential {
  if (credential) return credential;
  const tenant = required("AAD_TENANT_ID");
  const clientId = required("AAD_CLIENT_ID");
  const clientSecret = required("AAD_CLIENT_SECRET");
  credential = new ClientSecretCredential(tenant, clientId, clientSecret);
  return credential;
}

async function getToken(): Promise<string> {
  const now = Date.now();
  if (cached && cached.expiresOn - 60_000 > now) return cached.token;
  const result = await getCredential().getToken(SCOPE);
  if (!result?.token) throw new Error("Failed to acquire Graph token");
  cached = {
    token: result.token,
    expiresOn: result.expiresOnTimestamp ?? now + 50 * 60_000,
  };
  return cached.token;
}

/**
 * App-only Graph client (client-credentials flow).
 * Use for directory search, mail.send from a shared mailbox, etc.
 * For per-user data, switch to delegated/on-behalf-of — but read AGENTS.md first.
 */
export function getGraphClient(): Client {
  return Client.init({
    authProvider: async (done) => {
      try {
        const token = await getToken();
        done(null, token);
      } catch (err) {
        done(err as Error, null);
      }
    },
  });
}

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}
