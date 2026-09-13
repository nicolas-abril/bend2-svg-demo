// Bytes
// =====

// The whole file as a string with one character per byte (code 0..255).
function bytes_read_raw(path) {
  const fs = require("fs");
  let buf;
  try {
    buf = fs.readFileSync(path);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 2));
  }
  return io_done(buf.toString("latin1"));
}
