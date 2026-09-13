// Pixels
// ======

// Writes w by h packed 0xRRGGBB pixels as a P3 text matrix to standard output.
function pixels_write_flat(a, out, at) {
  if (a.$ === "ALeaf") {
    out[at] = a.value >>> 0;
    return at + 1;
  }
  return pixels_write_flat(a.ys, out, pixels_write_flat(a.xs, out, at));
}

function pixels_write(a, w, h) {
  const fs = require("fs");
  const words = new Uint32Array(array_len(a));
  pixels_write_flat(a, words, 0);
  const n = w * h, parts = [`P3\n${w} ${h}\n255\n`];
  for (let i = 0; i < n; i++) {
    const v = words[i];
    parts.push(`${(v >>> 16) & 255} ${(v >>> 8) & 255} ${v & 255}\n`);
  }
  try {
    fs.writeSync(1, parts.join(""));
  } catch (e) {
    return io_tup(a, io_fail(Math.abs(e.errno ?? 5)));
  }
  return io_tup(a, io_done({ $: "Unit" }));
}
