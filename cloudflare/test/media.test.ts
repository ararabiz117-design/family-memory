import test from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeImage, MAX_IMAGE_BYTES } from '../src/media.js';

const concat = (...parts: Uint8Array[]) => new Uint8Array(Buffer.concat(parts));
function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = Buffer.alloc(data.length + 12);
  out.writeUInt32BE(data.length); out.write(type, 4, 'ascii'); out.set(data, 8);
  let crc = 0xffffffff;
  for (const b of out.subarray(4, out.length - 4)) {
    crc ^= b;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  out.writeUInt32BE((crc ^ 0xffffffff) >>> 0, out.length - 4);
  return out;
}
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII=', 'base64');
const segment = (marker: number, body: number[] | Uint8Array) => concat(new Uint8Array([255, marker, (body.length + 2) >> 8, (body.length + 2) & 255]), new Uint8Array(body));
const jpeg = (meta = new Uint8Array()) => concat(new Uint8Array([255, 216]), meta,
  segment(0xc0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0]), segment(0xda, [1, 1, 0, 0, 63, 0]), new Uint8Array([1, 255, 0, 2, 255, 217]));

test('JPEG strips EXIF/GPS, comments and trailing payloads are rejected', async () => {
  const metadata = concat(segment(0xe1, Buffer.from('Exif\0\0GPS private-location')), segment(0xfe, Buffer.from('private-name')));
  const clean = await sanitizeImage(jpeg(metadata), 'image/jpeg');
  assert.deepEqual(clean.bytes, jpeg());
  assert.equal(clean.width, 1); assert.equal(clean.height, 1);
  assert.match(clean.sha256, /^[a-f0-9]{64}$/);
  await assert.rejects(sanitizeImage(concat(jpeg(), Buffer.from('payload')), 'image/jpeg'));
});

test('PNG removes EXIF, arbitrary ancillary text and ICC metadata', async () => {
  // Recompute sample data CRC so the test independently verifies all retained bytes.
  const idatLength = png.readUInt32BE(33);
  const canonical = concat(png.subarray(0, 33), chunk('IDAT', png.subarray(41, 41 + idatLength)), chunk('IEND', new Uint8Array()));
  const metadata = concat(chunk('eXIf', Buffer.from('GPS secret')), chunk('tEXt', Buffer.from('Name\0secret')), chunk('iCCP', Buffer.from('profile-secret')));
  const clean = await sanitizeImage(concat(canonical.subarray(0, 33), metadata, canonical.subarray(33)), 'image/png');
  assert.deepEqual(clean.bytes, canonical);
  assert.equal(clean.mime, 'image/png'); assert.equal(clean.width, 1);
});

test('rejects format confusion, excess bytes, corrupt CRC and unrecognized critical chunks', async () => {
  await assert.rejects(sanitizeImage(jpeg(), 'image/png'));
  await assert.rejects(sanitizeImage(png, 'image/svg+xml'));
  await assert.rejects(sanitizeImage(new Uint8Array(MAX_IMAGE_BYTES + 1), 'image/jpeg'));
  const corrupt = new Uint8Array(png); corrupt[20] ^= 1;
  await assert.rejects(sanitizeImage(corrupt, 'image/png'));
  await assert.rejects(sanitizeImage(concat(png.subarray(0, 33), chunk('ABCD', new Uint8Array()), png.subarray(33)), 'image/png'));
});

test('rejects oversized dimensions and malformed/truncated JPEG structure', async () => {
  const oversized = jpeg(); oversized[7] = 0x20; // height 8193
  await assert.rejects(sanitizeImage(oversized, 'image/jpeg'));
  await assert.rejects(sanitizeImage(jpeg().slice(0, -2), 'image/jpeg'));
  await assert.rejects(sanitizeImage(new Uint8Array([255, 216, 255, 0xe1, 255, 255, 0]), 'image/jpeg'));
});
