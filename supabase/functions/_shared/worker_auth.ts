function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (a[index % Math.max(a.length, 1)] ?? 0) ^
      (b[index % Math.max(b.length, 1)] ?? 0);
  }
  return difference === 0;
}

export function workerAuthorized(request: Request): boolean {
  const expected = Deno.env.get("LIFECYCLE_WORKER_SECRET");
  const supplied = request.headers.get("x-lifecycle-worker-secret") ?? "";
  return Boolean(expected) && constantTimeEqual(supplied, expected ?? "");
}
