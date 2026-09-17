// Lossless PNG transport for Bend's already rasterized 0xRRGGBB pixels.
// The web executable links zlib; this effect does no SVG rendering.
// zlib's historical FAR qualifier collides with the runtime's function macro.
#pragma push_macro("FAR")
#undef FAR
#include <zlib.h>
#pragma pop_macro("FAR")

static void frame_send_u32(uint8_t* p, uint32_t n) {
  p[0] = n >> 24; p[1] = n >> 16; p[2] = n >> 8; p[3] = n;
}

static uint8_t* frame_send_chunk(uint8_t* p, const char* type,
    const uint8_t* data, uint32_t n) {
  frame_send_u32(p, n);
  memcpy(p + 4, type, 4);
  if (n != 0) memcpy(p + 8, data, n);
  frame_send_u32(p + 8 + n, (uint32_t)crc32(0, p + 4, n + 4));
  return p + n + 12;
}

static void frame_send_call(IoWork* w) {
  uint64_t at = 0;
  while (at < w->size) {
    ssize_t n = send((int)w->hand, w->data + at, w->size - at, 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) {
      if (n == 0) errno = EPIPE;
      io_sys_end(w, -1);
      return;
    }
    at += (uint64_t)n;
  }
  io_sys_end(w, 0);
}

static Term frame_send_pack(Env e, IoWork* w) {
  Term result = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  free(w->data);
  return io_tup(e, io_hand(w->hand), result);
}

Term frame_send_run(Env e, Term* f, IoWork* work) {
  Term pixels = f[1];
  u32 w = (u32)f[2], h = (u32)f[3];
  if (w < 1 || h < 1 || w > 4096 || h > 4096) {
    term_drop(e, pixels);
    return io_tup(e, f[0], io_fail(e, EINVAL, NULL));
  }
  u64 stride = 1 + (u64)w * 3, size = stride * h;
  uint8_t* raw = io_mem(malloc(size));
  Loc loc = term_peek(e, pixels);
  for (u32 y = 0; y < h; y++) {
    uint8_t* row = raw + y * stride;
    row[0] = 1; // PNG Sub filter.
    u32 previous = 0;
    for (u32 x = 0; x < w; x++) {
      u32 pixel = (u32)blk_read(e.mem, 0, loc, y * w + x);
      for (u32 c = 0; c < 3; c++) {
        u32 shift = 16 - c * 8;
        row[1 + x * 3 + c] = (uint8_t)((pixel >> shift) - (previous >> shift));
      }
      previous = pixel;
    }
  }
  term_drop(e, pixels);
  uLongf compressed_size = compressBound((uLong)size);
  uint8_t* compressed = io_mem(malloc(compressed_size));
  int code = compress2(compressed, &compressed_size, raw, (uLong)size, Z_BEST_SPEED);
  free(raw);
  if (code != Z_OK) {
    free(compressed);
    return io_tup(e, f[0], io_fail(e, EIO, NULL));
  }
  u64 png_size = 57 + compressed_size;
  char* response = io_mem(malloc(256 + png_size));
  int header_size = snprintf(response, 256,
    "HTTP/1.1 200 OK\r\nConnection: close\r\nCache-Control: no-store\r\n"
    "Content-Type: image/png\r\nContent-Length: %llu\r\n\r\n",
    (unsigned long long)png_size);
  uint8_t* p = (uint8_t*)response + header_size;
  const uint8_t signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
  memcpy(p, signature, 8); p += 8;
  uint8_t ihdr[13] = {0};
  frame_send_u32(ihdr, w); frame_send_u32(ihdr + 4, h);
  ihdr[8] = 8; ihdr[9] = 2;
  p = frame_send_chunk(p, "IHDR", ihdr, 13);
  p = frame_send_chunk(p, "IDAT", compressed, (uint32_t)compressed_size);
  frame_send_chunk(p, "IEND", NULL, 0);
  free(compressed);
  work->hand = (intptr_t)io_hand_v(f[0]);
  work->data = response;
  work->size = header_size + png_size;
  return io_work(work, frame_send_call, frame_send_pack);
}

static void __attribute__((constructor)) frame_send_use(void) {
  io_eff(CID_FRAME_SEND, frame_send_run, 0);
}
