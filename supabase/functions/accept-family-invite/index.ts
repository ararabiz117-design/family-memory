import { userClient } from "../_shared/auth_client.ts";
import { json, preflight, publicError } from "../_shared/http.ts";

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request) => {
  const options = preflight(request); if (options) return options;
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  try {
    const body = await request.json() as { token?: string; shortCode?: string };
    const value = body.token?.trim() || body.shortCode?.trim().toUpperCase();
    if (!value || Boolean(body.token) === Boolean(body.shortCode)) return json(400, { code: "VALIDATION_FAILED" });
    const client = userClient(request);
    const { data, error } = await client.rpc("accept_family_invitation", {
      p_hash_hex: await sha256Hex(value), p_is_short_code: Boolean(body.shortCode),
    });
    if (error) throw error;
    return json(200, { invitationId: data, status: "pending_owner_approval" });
  } catch (error) {
    const safe = publicError(error); return json(safe.status, { code: safe.code });
  }
});

