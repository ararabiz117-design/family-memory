/** Metadata sanitization, not a pixel decoder. Client must first decode, orient and resize. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const MAX_IMAGE_DIMENSION = 4096;
export const CLIENT_IMAGE_DIMENSION = 1600;

export interface SanitizedImage {
  bytes: Uint8Array;
  mime: 'image/jpeg' | 'image/png';
  width: number;
  height: number;
  sha256: string;
}

export class ImageValidationError extends Error {
  constructor(message: string) { super(message); this.name = 'ImageValidationError'; }
}

const fail = (message: string): never => { throw new ImageValidationError(message); };
const u16 = (b: Uint8Array, p: number) => (b[p]! << 8) | b[p + 1]!;
const u32 = (b: Uint8Array, p: number) => new DataView(b.buffer, b.byteOffset, b.byteLength).getUint32(p);
const dimensions = (w: number, h: number) => {
  if (!w || !h || w > MAX_IMAGE_DIMENSION || h > MAX_IMAGE_DIMENSION || w * h > 16_000_000) fail('画像を4096px以下へ縮小してください。');
};
const join = (parts: Uint8Array[]) => {
  const result = new Uint8Array(parts.reduce((n, part) => n + part.length, 0));
  let p = 0;
  for (const part of parts) { result.set(part, p); p += part.length; }
  return result;
};

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff;
  for (const value of data) {
    crc ^= value;
    for (let n = 0; n < 8; n++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function png(input: Uint8Array): Omit<SanitizedImage, 'sha256'> {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (!signature.every((v, i) => input[i] === v)) fail('PNGの形式が正しくありません。');
  const parts = [input.slice(0, 8)];
  let p = 8, width = 0, height = 0, color = -1, chunks = 0;
  let hasHeader = false, hasData = false, dataEnded = false, hasPalette = false, hasTransparency = false;
  while (p < input.length && ++chunks <= 4096) {
    if (input.length - p < 12) fail('PNGが途中で切れています。');
    const length = u32(input, p);
    const end = p + length + 12;
    if (end > input.length) fail('PNGの長さが正しくありません。');
    const type = String.fromCharCode(...input.subarray(p + 4, p + 8));
    if (!/^[A-Za-z]{4}$/.test(type) || (input[p + 6]! & 32) !== 0) fail('PNGチャンクが不正です。');
    if (crc32(input.subarray(p + 4, end - 4)) !== u32(input, end - 4)) fail('PNGの検証に失敗しました。');
    if (!hasHeader && type !== 'IHDR') fail('PNGヘッダーがありません。');
    if (hasData && type !== 'IDAT') dataEnded = true;
    if (type === 'IHDR') {
      if (hasHeader || length !== 13) fail('PNGヘッダーが不正です。');
      width = u32(input, p + 8); height = u32(input, p + 12); dimensions(width, height);
      color = input[p + 17]!;
      const depths: Record<number, number[]> = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
      if (!depths[color]?.includes(input[p + 16]!) || input[p + 18] !== 0 || input[p + 19] !== 0 || input[p + 20]! > 1) fail('未対応のPNGです。');
      hasHeader = true;
    } else if (type === 'PLTE') {
      if (hasPalette || hasData || !length || length > 768 || length % 3 || color === 0 || color === 4) fail('PNGパレットが不正です。');
      hasPalette = true;
    } else if (type === 'tRNS') {
      if (hasTransparency || hasData || (color === 0 ? length !== 2 : color === 2 ? length !== 6 : color === 3 ? (!hasPalette || !length || length > 256) : true)) fail('PNG透過情報が不正です。');
      hasTransparency = true;
    } else if (type === 'IDAT') {
      if (dataEnded || (color === 3 && !hasPalette)) fail('PNG画像情報の順序が不正です。');
      hasData = true;
    } else if (type === 'IEND') {
      if (length || !hasData || end !== input.length) fail('PNGの終端が不正です。');
      parts.push(input.slice(p, end));
      return { bytes: join(parts), mime: 'image/png', width, height };
    } else if ((input[p + 4]! & 32) === 0) {
      fail('未対応のPNGチャンクです。');
    }
    // Whitelist only image-critical data and alpha; EXIF/text/location/animation is removed.
    if (['IHDR', 'PLTE', 'tRNS', 'IDAT'].includes(type)) parts.push(input.slice(p, end));
    p = end;
  }
  return fail('PNGの終端がありません。');
}

function jpeg(input: Uint8Array): Omit<SanitizedImage, 'sha256'> {
  if (input[0] !== 0xff || input[1] !== 0xd8) fail('JPEGの形式が正しくありません。');
  const parts = [input.slice(0, 2)];
  let p = 2, width = 0, height = 0, hasFrame = false, hasScan = false, segments = 0;
  while (p < input.length && ++segments <= 4096) {
    const start = p;
    if (input[p++] !== 0xff) fail('JPEGマーカーが不正です。');
    while (input[p] === 0xff) p++;
    const marker = input[p++];
    if (marker === 0xd9) {
      if (!hasFrame || !hasScan || p !== input.length) fail('JPEGの終端が不正です。');
      parts.push(new Uint8Array([0xff, 0xd9]));
      return { bytes: join(parts), mime: 'image/jpeg', width, height };
    }
    if (marker === undefined || p + 2 > input.length) fail('JPEGが途中で切れています。');
    const length = u16(input, p), end = p + length;
    if (length < 2 || end > input.length) fail('JPEGの長さが不正です。');
    const metadata = (marker! >= 0xe0 && marker! <= 0xef) || marker === 0xfe;
    if ([0xc0, 0xc1, 0xc2].includes(marker!)) {
      if (hasFrame || length < 8) fail('JPEGフレームが不正です。');
      height = u16(input, p + 3); width = u16(input, p + 5); dimensions(width, height);
      const components = input[p + 7]!;
      if (input[p + 2] !== 8 || ![1, 3].includes(components) || length !== 8 + 3 * components) fail('未対応のJPEGです。');
      hasFrame = true;
    } else if (marker === 0xda) {
      if (!hasFrame || length < 6 || length !== 6 + 2 * input[p + 2]!) fail('JPEGスキャンが不正です。');
      hasScan = true;
    } else if (!metadata && ![0xc4, 0xdb, 0xdd].includes(marker!)) {
      fail('未対応のJPEGマーカーです。');
    }
    if (!metadata) parts.push(input.slice(start, end));
    p = end;
    if (marker === 0xda) {
      const scanStart = p;
      while (p < input.length) {
        if (input[p] !== 0xff) { p++; continue; }
        const next = input[p + 1];
        if (next === 0 || (next !== undefined && next >= 0xd0 && next <= 0xd7)) { p += 2; continue; }
        break;
      }
      parts.push(input.slice(scanStart, p));
    }
  }
  return fail('JPEGの終端がありません。');
}

export async function sanitizeImage(bytes: Uint8Array, mime: string): Promise<SanitizedImage> {
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > MAX_IMAGE_BYTES) fail('画像は5MB以下にしてください。');
  let result: Omit<SanitizedImage, 'sha256'>;
  if (mime.toLowerCase() === 'image/jpeg') result = jpeg(bytes);
  else if (mime.toLowerCase() === 'image/png') result = png(bytes);
  else return fail('JPEGまたはPNGを選んでください。');
  const digest = await crypto.subtle.digest('SHA-256', result.bytes.slice().buffer);
  return { ...result, sha256: Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('') };
}
