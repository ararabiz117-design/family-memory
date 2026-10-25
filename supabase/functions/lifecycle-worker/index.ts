import { adminClient } from "../_shared/admin_client.ts";
import { json } from "../_shared/http.ts";
import { workerAuthorized } from "../_shared/worker_auth.ts";

type DeletionJob = {
  id: string;
  scope: "account" | "family";
  target_user_id: string | null;
  target_family_id: string | null;
};
type CleanupCandidate = { storage_path: string; remove_attachment_metadata: boolean };

function workerCode(scope: string): string {
  return scope === "family" ? "FAMILY_PURGE_FAILED" : "ACCOUNT_PURGE_FAILED";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });
  if (!workerAuthorized(request)) return json(401, { code: "AUTH_REQUIRED" });

  const client = adminClient();
  const summary = { completed: 0, failed: 0, storageObjectsRemoved: 0, metadataRowsRemoved: 0 };
  const { data: claimed, error: claimError } = await client.rpc("claim_due_deletion_jobs_v1", { p_limit: 20 });
  if (claimError) return json(500, { code: "WORKER_CLAIM_FAILED" });

  for (const job of (claimed ?? []) as DeletionJob[]) {
    try {
      if (job.scope === "family") {
        while (true) {
          const { data: paths, error: pathsError } = await client.rpc("list_family_storage_paths_v1", {
            p_job_id: job.id, p_limit: 500,
          });
          if (pathsError) throw pathsError;
          const names = (paths ?? []).map((row: { storage_path: string }) => row.storage_path);
          if (!names.length) break;
          for (let offset = 0; offset < names.length; offset += 100) {
            const batch = names.slice(offset, offset + 100);
            const { error } = await client.storage.from("family-private").remove(batch);
            if (error) throw error;
            summary.storageObjectsRemoved += batch.length;
          }
        }
        const { error } = await client.rpc("purge_family_v1", { p_job_id: job.id });
        if (error) throw error;
      } else {
        if (!job.target_user_id) throw new Error("JOB_INVALID");
        const { error } = await client.auth.admin.deleteUser(job.target_user_id, false);
        if (error) throw error;
        const { error: completionError } = await client.rpc("complete_account_deletion_job_v1", { p_job_id: job.id });
        if (completionError) throw completionError;
      }
      summary.completed += 1;
    } catch (_error) {
      summary.failed += 1;
      await client.rpc("fail_deletion_job_v1", {
        p_job_id: job.id, p_error_code: workerCode(job.scope),
      });
    }
  }

  const { data: candidates, error: cleanupListError } = await client.rpc("list_storage_cleanup_candidates_v1", { p_limit: 500 });
  if (!cleanupListError) {
    const rows = (candidates ?? []) as CleanupCandidate[];
    const removedPaths: string[] = [];
    for (let offset = 0; offset < rows.length; offset += 100) {
      const batch = rows.slice(offset, offset + 100).map((row) => row.storage_path);
      const { error } = await client.storage.from("family-private").remove(batch);
      if (!error) {
        removedPaths.push(...batch);
        summary.storageObjectsRemoved += batch.length;
      }
    }
    if (removedPaths.length) {
      const { data: removedMetadata } = await client.rpc("finalize_storage_cleanup_v1", {
        p_storage_paths: removedPaths,
      });
      summary.metadataRowsRemoved = Number(removedMetadata ?? 0);
    }
  }

  return json(200, { status: "completed", ...summary });
});
