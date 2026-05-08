import type { HttpRequest } from "@azure/functions";

export interface ClientPrincipal {
  identityProvider: string;
  userId: string;
  userDetails: string;
  userRoles: string[];
  claims?: Array<{ typ?: string; val?: string }>;
}

/**
 * Decode the SWA-injected x-ms-client-principal header.
 * Returns null if the header is absent or malformed.
 *
 * EasyAuth gates /api/* at the SWA layer, but every endpoint must still call this
 * helper — defense in depth and the source of truth for the user's identity.
 */
export function getPrincipal(req: HttpRequest): ClientPrincipal | null {
  const header = req.headers.get("x-ms-client-principal");
  if (!header) return null;
  try {
    const decoded = Buffer.from(header, "base64").toString("utf8");
    const parsed = JSON.parse(decoded) as ClientPrincipal;
    if (!parsed.userId || !parsed.userDetails) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function requirePrincipal(req: HttpRequest): ClientPrincipal {
  const p = getPrincipal(req);
  if (!p) throw new AuthError("Missing or invalid client principal");
  return p;
}

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}
