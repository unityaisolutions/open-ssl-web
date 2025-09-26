/**
 * WebOpenSSL (ESM)
 * Provides OpenSSL-like random key generation via WebCrypto or optional OpenSSL WASM module.
 * Exports: randBytes, randBase64, randHex, setProvider, setWasmModule, getProviderName
 */

let _provider = createDefaultProvider();

function createDefaultProvider() {
  if (typeof globalThis !== "undefined" && globalThis.crypto && typeof globalThis.crypto.getRandomValues === "function") {
    return {
      name: "webcrypto",
      randBytes(length) {
        if (!Number.isInteger(length) || length <= 0) throw new Error("length must be a positive integer");
        const arr = new Uint8Array(length);
        globalThis.crypto.getRandomValues(arr);
        return arr;
      }
    };
  }
  throw new Error("Secure random provider not available (WebCrypto is required in browser environments)");
}

export function setProvider(p) {
  if (!p || typeof p.randBytes !== "function") throw new Error("Invalid provider: must implement randBytes(length): Uint8Array");
  _provider = p;
}

export function getProviderName() {
  return (_provider && _provider.name) || "unknown";
}

export function randBytes(length) {
  if (!Number.isInteger(length) || length <= 0) throw new Error("length must be a positive integer");
  return _provider.randBytes(length);
}

function bytesToBase64(bytes) {
  // Node Buffer path if available (useful in some bundlers/runtime combos)
  if (typeof Buffer !== "undefined" && typeof Buffer.from === "function") {
    return Buffer.from(bytes).toString("base64");
  }
  // Browser path
  let binary = "";
  const chunkSize = 0x8000; // avoid call stack limits
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function bytesToHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) {
    let h = bytes[i].toString(16);
    if (h.length < 2) h = "0" + h;
    s += h;
  }
  return s;
}

export function randBase64(length) {
  return bytesToBase64(randBytes(length));
}

export function randHex(length) {
  return bytesToHex(randBytes(length));
}

/**
 * Configure OpenSSL WASM module (Emscripten-compiled libcrypto exposing RAND_bytes).
 * Module must provide: cwrap, _malloc, _free, HEAPU8
 */
function wasmOpenSSLProvider(Module) {
  if (!Module || !Module.cwrap || !Module._malloc || !Module._free || !Module.HEAPU8) {
    throw new Error("Invalid OpenSSL WASM Module: expected cwrap, _malloc, _free, HEAPU8");
  }
  const RAND_bytes = Module.cwrap("RAND_bytes", "number", ["number", "number"]);
  return {
    name: "openssl-wasm",
    randBytes(length) {
      if (!Number.isInteger(length) || length <= 0) throw new Error("length must be a positive integer");
      const ptr = Module._malloc(length);
      const ret = RAND_bytes(ptr, length);
      if (ret !== 1) {
        Module._free(ptr);
        throw new Error("RAND_bytes failed");
      }
      const out = new Uint8Array(length);
      out.set(Module.HEAPU8.subarray(ptr, ptr + length));
      Module._free(ptr);
      return out;
    }
  };
}

export function setWasmModule(Module) {
  setProvider(wasmOpenSSLProvider(Module));
}