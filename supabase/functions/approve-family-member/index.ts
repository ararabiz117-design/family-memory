import { userClient } from "../_shared/auth_client.ts";
import { json, preflight, publicError } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const options = preflight(request); if (options) return options;
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  try {
    const body = await request.json() as { invitationId?: string };
    if (!body.invitationId) return json(400, { code: "VALIDATION_FAILED" });
    const client = userClient(request);
    const { error } = await client.rpc("approve_family_member", { p_invitation_id: body.invitationId });
    if (error) throw error;
    return json(200, { status: "approved" });
  } catch (error) {
    const safe = publicError(error); return json(safe.status, { code: safe.code });
  }
});

