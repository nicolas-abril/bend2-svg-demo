// Lossless PNG transport for Bend's already rasterized 0xRRGGBB pixels.
const frame_send_crc_table = Uint32Array.from({length: 256}, (_, n) => {
  for (let i = 0; i < 8; i++) n = (n >>> 1) ^ ((n & 1) ? 0xedb88320 : 0);
  return n >>> 0;
});

function frame_send_chunk(type, data) {
  const chunk = Buffer.alloc(data.length + 12);
  chunk.writeUInt32BE(data.length, 0);
  chunk.write(type, 4, 4, "ascii");
  data.copy(chunk, 8);
  let crc = 0xffffffff;
  for (let i = 4; i < chunk.length - 4; i++) {
    crc = (crc >>> 8) ^ frame_send_crc_table[(crc ^ chunk[i]) & 255];
  }
  chunk.writeUInt32BE((crc ^ 0xffffffff) >>> 0, chunk.length - 4);
  return chunk;
}

function frame_send_png(pixels, w, h) {
  if (w < 1 || h < 1 || w > 4096 || h > 4096) throw Error("Invalid frame size");
  const stride = 1 + w * 3, raw = Buffer.alloc(stride * h);
  for (let y = 0; y < h; y++) {
    const row = y * stride;
    raw[row] = 1; // PNG Sub filter: differences from the previous RGB pixel.
    let previous = 0;
    for (let x = 0; x < w; x++) {
      const pixel = pixels[y * w + x];
      for (let c = 0; c < 3; c++) {
        const shift = 16 - c * 8;
        raw[row + 1 + x * 3 + c] = ((pixel >>> shift) - (previous >>> shift)) & 255;
      }
      previous = pixel;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; // Eight-bit RGB, no interlacing.
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    frame_send_chunk("IHDR", ihdr),
    frame_send_chunk("IDAT", require("node:zlib").deflateSync(raw, {level: 1})),
    frame_send_chunk("IEND", Buffer.alloc(0)),
  ]);
}

function frame_send(socket, pixels, w, h) {
  try {
    const png = frame_send_png(pixels, w, h);
    const header = Buffer.from("HTTP/1.1 200 OK\r\nConnection: close\r\n"
      + "Cache-Control: no-store\r\nContent-Type: image/png\r\n"
      + `Content-Length: ${png.length}\r\n\r\n`);
    const data = Buffer.concat([header, png]), sys = io_sys();
    let at = 0;
    while (at < data.length) {
      const part = data.subarray(at);
      const n = Number(sys.send(socket, sys.ptr(part), part.length, 0));
      if (n < 0) {
        const code = sys.errno();
        if (code === 4) continue; // EINTR
        return io_tup(socket, io_fail(code));
      }
      if (n === 0) return io_tup(socket, io_fail(32)); // EPIPE
      at += n;
    }
    return io_tup(socket, io_done({$: "Unit"}));
  } catch (error) {
    return io_tup(socket, io_fail(Math.abs(error.errno ?? 5)));
  }
}
