import { userClient } from "../_shared/auth_client.ts";
import { json, preflight, publicError } from "../_shared/http.ts";

function randomUrlToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function randomCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map((value) => alphabet[value % alphabet.length]).join("");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request) => {
  const options = preflight(request); if (options) return options;
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  try {
    const body = await request.json() as { familyId?: string; invitedEmail?: string; role?: "editor" | "viewer" };
    const invitedEmail = body.invitedEmail?.trim().toLowerCase();
    if (!body.familyId || !invitedEmail || !invitedEmail.includes("@") || !["editor", "viewer"].includes(body.role ?? "")) return json(400, { code: "VALIDATION_FAILED" });
    const token = randomUrlToken();
    const code = randomCode();
    const client = userClient(request);
    const { data, error } = await client.rpc("create_family_invitation", {
      p_family_id: body.familyId,
      p_token_hash_hex: await sha256Hex(token),
      p_short_code_hash_hex: await sha256Hex(code),
      p_invited_email_hash_hex: await sha256Hex(invitedEmail),
      p_role: body.role,
    });
    if (error) throw error;
    const base = Deno.env.get("INVITE_APP_LINK_BASE") ?? "familymemory://invite";
    return json(201, { invitationId: data, inviteUrl: `${base}?token=${encodeURIComponent(token)}`, shortCode: code, expiresInSeconds: 86400 });
  } catch (error) {
    const safe = publicError(error); return json(safe.status, { code: safe.code });
  }
});
