import { z } from "zod";

export const ClientPrincipalSchema = z.object({
  identityProvider: z.string(),
  userId: z.string(),
  userDetails: z.string(),
  userRoles: z.array(z.string()),
  claims: z
    .array(
      z.object({
        typ: z.string().optional(),
        val: z.string().optional(),
      }),
    )
    .optional(),
});

export type ClientPrincipal = z.infer<typeof ClientPrincipalSchema>;

export async function fetchPrincipal(): Promise<ClientPrincipal | null> {
  const res = await fetch("/.auth/me");
  if (!res.ok) return null;
  const json = (await res.json()) as { clientPrincipal: unknown };
  if (!json.clientPrincipal) return null;
  return ClientPrincipalSchema.parse(json.clientPrincipal);
}
