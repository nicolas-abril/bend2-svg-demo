// Pixels
// ======

// Writes w by h packed 0xRRGGBB pixels as a P3 text matrix to standard
// output; an array is a plain JavaScript array of its words.
function pixels_write(a, w, h) {
  const fs = require("fs");
  const words = a;
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
