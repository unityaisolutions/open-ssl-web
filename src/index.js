/**
 * WebOpenSSL (ESM)
 * Provides OpenSSL-like random key generation via WebCrypto or optional OpenSSL WASM module.
 * Exports: randBytes, randBase64, randHex, setProvider, setWasmModule, getProviderName, autoLoadOpenSSLWASM
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
  if (typeof Buffer !== "undefined" && typeof Buffer.from === "function") {
    return Buffer.from(bytes).toString("base64");
  }
  let binary = "";
  const chunkSize = 0x8000;
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
 * Configure OpenSSL WASM module (Emscripten-compiled libcrypto exposing openssl_rand_bytes or RAND_bytes).
 * Module must provide: cwrap, _malloc, _free, HEAPU8
 */
function wasmOpenSSLProvider(Module) {
  if (!Module || !Module.cwrap || !Module._malloc || !Module._free || !Module.HEAPU8) {
    throw new Error("Invalid OpenSSL WASM Module: expected cwrap, _malloc, _free, HEAPU8");
  }
  let randFn;
  try { randFn = Module.cwrap("openssl_rand_bytes", "number", ["number", "number"]); } catch (_) {}
  if (!randFn) {
    try { randFn = Module.cwrap("RAND_bytes", "number", ["number", "number"]); } catch (_) {}
  }
  if (!randFn) {
    throw new Error("Missing RAND function in Module (expected openssl_rand_bytes or RAND_bytes)");
  }

  // Optional additional OpenSSL exports
  let pbkdf2_sha256, pbkdf2_sha512, sha256_digest, sha512_digest, aes_256_gcm_encrypt, aes_256_gcm_decrypt;
  try { pbkdf2_sha256 = Module.cwrap("pbkdf2_hmac_sha256", "number", ["number","number","number","number","number","number","number"]); } catch (_) {}
  try { pbkdf2_sha512 = Module.cwrap("pbkdf2_hmac_sha512", "number", ["number","number","number","number","number","number","number"]); } catch (_) {}
  try { sha256_digest = Module.cwrap("sha256_digest", "number", ["number","number","number"]); } catch (_) {}
  try { sha512_digest = Module.cwrap("sha512_digest", "number", ["number","number","number"]); } catch (_) {}
  try { aes_256_gcm_encrypt = Module.cwrap("aes_256_gcm_encrypt", "number", ["number","number","number","number","number","number","number","number","number"]); } catch (_) {}
  try { aes_256_gcm_decrypt = Module.cwrap("aes_256_gcm_decrypt", "number", ["number","number","number","number","number","number","number","number","number"]); } catch (_) {}

  function mallocCopy(bytes) {
    const ptr = Module._malloc(bytes.length);
    Module.HEAPU8.set(bytes, ptr);
    return ptr;
  }
  function copyOut(ptr, len) {
    const out = new Uint8Array(len);
    out.set(Module.HEAPU8.subarray(ptr, ptr + len));
    return out;
  }

  return {
    name: "openssl-wasm",
    randBytes(length) {
      if (!Number.isInteger(length) || length <= 0) throw new Error("length must be a positive integer");
      const ptr = Module._malloc(length);
      const ret = randFn(ptr, length);
      if (ret !== 1) {
        Module._free(ptr);
        throw new Error("RAND failed");
      }
      const out = new Uint8Array(length);
      out.set(Module.HEAPU8.subarray(ptr, ptr + length));
      Module._free(ptr);
      return out;
    },

    // Hashing
    sha256(bytes) {
      if (!sha256_digest) throw new Error("sha256_digest not exported by OpenSSL WASM");
      if (!(bytes instanceof Uint8Array)) throw new Error("bytes must be Uint8Array");
      const inPtr = mallocCopy(bytes);
      const outPtr = Module._malloc(32);
      const ret = sha256_digest(inPtr, bytes.length, outPtr);
      Module._free(inPtr);
      if (ret !== 1) { Module._free(outPtr); throw new Error("sha256 failed"); }
      const out = copyOut(outPtr, 32);
      Module._free(outPtr);
      return out;
    },

    sha512(bytes) {
      if (!sha512_digest) throw new Error("sha512_digest not exported by OpenSSL WASM");
      if (!(bytes instanceof Uint8Array)) throw new Error("bytes must be Uint8Array");
      const inPtr = mallocCopy(bytes);
      const outPtr = Module._malloc(64);
      const ret = sha512_digest(inPtr, bytes.length, outPtr);
      Module._free(inPtr);
      if (ret !== 1) { Module._free(outPtr); throw new Error("sha512 failed"); }
      const out = copyOut(outPtr, 64);
      Module._free(outPtr);
      return out;
    },

    // PBKDF2
    pbkdf2HmacSha256(passwordBytes, saltBytes, iterations, keyLen) {
      if (!pbkdf2_sha256) throw new Error("pbkdf2_hmac_sha256 not exported by OpenSSL WASM");
      if (!(passwordBytes instanceof Uint8Array)) throw new Error("passwordBytes must be Uint8Array");
      if (!(saltBytes instanceof Uint8Array)) throw new Error("saltBytes must be Uint8Array");
      if (!Number.isInteger(iterations) || iterations <= 0) throw new Error("iterations must be a positive integer");
      if (!Number.isInteger(keyLen) || keyLen <= 0) throw new Error("keyLen must be a positive integer");
      const passPtr = mallocCopy(passwordBytes);
      const saltPtr = mallocCopy(saltBytes);
      const outPtr = Module._malloc(keyLen);
      const ret = pbkdf2_sha256(passPtr, passwordBytes.length, saltPtr, saltBytes.length, iterations, outPtr, keyLen);
      Module._free(passPtr);
      Module._free(saltPtr);
      if (ret !== 1) { Module._free(outPtr); throw new Error("PBKDF2-HMAC-SHA256 failed"); }
      const out = copyOut(outPtr, keyLen);
      Module._free(outPtr);
      return out;
    },

    pbkdf2HmacSha512(passwordBytes, saltBytes, iterations, keyLen) {
      if (!pbkdf2_sha512) throw new Error("pbkdf2_hmac_sha512 not exported by OpenSSL WASM");
      if (!(passwordBytes instanceof Uint8Array)) throw new Error("passwordBytes must be Uint8Array");
      if (!(saltBytes instanceof Uint8Array)) throw new Error("saltBytes must be Uint8Array");
      if (!Number.isInteger(iterations) || iterations <= 0) throw new Error("iterations must be a positive integer");
      if (!Number.isInteger(keyLen) || keyLen <= 0) throw new Error("keyLen must be a positive integer");
      const passPtr = mallocCopy(passwordBytes);
      const saltPtr = mallocCopy(saltBytes);
      const outPtr = Module._malloc(keyLen);
      const ret = pbkdf2_sha512(passPtr, passwordBytes.length, saltPtr, saltBytes.length, iterations, outPtr, keyLen);
      Module._free(passPtr);
      Module._free(saltPtr);
      if (ret !== 1) { Module._free(outPtr); throw new Error("PBKDF2-HMAC-SHA512 failed"); }
      const out = copyOut(outPtr, keyLen);
      Module._free(outPtr);
      return out;
    },

    // AES-256-GCM
    aes256GcmEncrypt(key, iv, aad, plaintext) {
      if (!aes_256_gcm_encrypt) throw new Error("aes_256_gcm_encrypt not exported by OpenSSL WASM");
      if (!(key instanceof Uint8Array) || key.length !== 32) throw new Error("key must be 32-byte Uint8Array");
      if (!(iv instanceof Uint8Array)) throw new Error("iv must be Uint8Array");
      if (!(aad instanceof Uint8Array)) aad = new Uint8Array(0);
      if (!(plaintext instanceof Uint8Array)) throw new Error("plaintext must be Uint8Array");
      const keyPtr = mallocCopy(key);
      const ivPtr = mallocCopy(iv);
      const aadPtr = mallocCopy(aad);
      const inPtr = mallocCopy(plaintext);
      const outPtr = Module._malloc(plaintext.length + 16);
      const tagPtr = Module._malloc(16);

      const ret = aes_256_gcm_encrypt(keyPtr, ivPtr, iv.length, aadPtr, aad.length, inPtr, plaintext.length, outPtr, tagPtr);

      Module._free(keyPtr);
      Module._free(ivPtr);
      Module._free(aadPtr);
      Module._free(inPtr);

      if (ret < 0) {
        Module._free(outPtr);
        Module._free(tagPtr);
        throw new Error("AES-256-GCM encrypt failed");
      }

      const ciphertext = copyOut(outPtr, ret);
      const tag = copyOut(tagPtr, 16);

      Module._free(outPtr);
      Module._free(tagPtr);

      return { ciphertext, tag };
    },

    aes256GcmDecrypt(key, iv, aad, ciphertext, tag) {
      if (!aes_256_gcm_decrypt) throw new Error("aes_256_gcm_decrypt not exported by OpenSSL WASM");
      if (!(key instanceof Uint8Array) || key.length !== 32) throw new Error("key must be 32-byte Uint8Array");
      if (!(iv instanceof Uint8Array)) throw new Error("iv must be Uint8Array");
      if (!(aad instanceof Uint8Array)) aad = new Uint8Array(0);
      if (!(ciphertext instanceof Uint8Array)) throw new Error("ciphertext must be Uint8Array");
      if (!(tag instanceof Uint8Array) || tag.length !== 16) throw new Error("tag must be 16-byte Uint8Array");
      const keyPtr = mallocCopy(key);
      const ivPtr = mallocCopy(iv);
      const aadPtr = mallocCopy(aad);
      const inPtr = mallocCopy(ciphertext);
      const tagPtr = mallocCopy(tag);
      const outPtr = Module._malloc(ciphertext.length);

      const ret = aes_256_gcm_decrypt(keyPtr, ivPtr, iv.length, aadPtr, aad.length, inPtr, ciphertext.length, tagPtr, outPtr);

      Module._free(keyPtr);
      Module._free(ivPtr);
      Module._free(aadPtr);
      Module._free(inPtr);
      Module._free(tagPtr);

      if (ret < 0) {
        Module._free(outPtr);
        throw new Error("AES-256-GCM decrypt failed or authentication tag mismatch");
      }

      const plaintext = copyOut(outPtr, ret);
      Module._free(outPtr);
      return plaintext;
    }
  };
}

export function setWasmModule(Module) {
  setProvider(wasmOpenSSLProvider(Module));
}

/**
 * Attempt to auto-load the OpenSSL WASM module and configure the provider.
 * options: { url?: string, factoryGlobalName?: string }
 * - url: path to the modularized JS emitted by Emscripten (default: "./dist/openssl-wasm/openssl_module.js")
 * - factoryGlobalName: if the factory is already on globalThis, its name (default: "OpenSSLModuleFactory")
 */
export async function autoLoadOpenSSLWASM(options = {}) {
  const jsUrl = options.url || "./dist/openssl-wasm/openssl_module.js";
  const factoryName = options.factoryGlobalName || "OpenSSLModuleFactory";

  function loadScript(u) {
    return new Promise((resolve, reject) => {
      if (typeof document === "undefined") return reject(new Error("Script loader only available in browsers"));
      const s = document.createElement("script");
      s.src = u;
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error("Failed to load " + u));
      document.head.appendChild(s);
    });
  }

  function deriveWasmUrlFromJs(u) {
    try {
      const abs = new URL(u, typeof document !== "undefined" ? document.baseURI : (globalThis && globalThis.location ? globalThis.location.href : undefined));
      abs.pathname = abs.pathname.replace(/\.js$/, ".wasm");
      return abs.toString();
    } catch (_) {
      return u.replace(/\.js$/, ".wasm");
    }
  }

  let factory = globalThis[factoryName];
  if (!factory) {
    await loadScript(jsUrl).catch(() => {});
    factory = globalThis[factoryName];
  }
  if (!factory) {
    return false;
  }

  const wasmUrl = deriveWasmUrlFromJs(jsUrl);

  const Module = await factory({
    locateFile: (p) => (p && p.endsWith(".wasm")) ? wasmUrl : p,
    wasmBinaryFile: wasmUrl
  });

  setWasmModule(Module);
  return true;
}

/* Additional top-level APIs (available only when using the OpenSSL WASM provider) */
export function sha256(bytes) {
  if (!_provider || typeof _provider.sha256 !== "function") throw new Error("sha256 not available (requires OpenSSL WASM provider)");
  return _provider.sha256(bytes);
}

export function sha512(bytes) {
  if (!_provider || typeof _provider.sha512 !== "function") throw new Error("sha512 not available (requires OpenSSL WASM provider)");
  return _provider.sha512(bytes);
}

export function pbkdf2HmacSha256(passwordBytes, saltBytes, iterations, keyLen) {
  if (!_provider || typeof _provider.pbkdf2HmacSha256 !== "function") throw new Error("pbkdf2HmacSha256 not available (requires OpenSSL WASM provider)");
  return _provider.pbkdf2HmacSha256(passwordBytes, saltBytes, iterations, keyLen);
}

export function pbkdf2HmacSha512(passwordBytes, saltBytes, iterations, keyLen) {
  if (!_provider || typeof _provider.pbkdf2HmacSha512 !== "function") throw new Error("pbkdf2HmacSha512 not available (requires OpenSSL WASM provider)");
  return _provider.pbkdf2HmacSha512(passwordBytes, saltBytes, iterations, keyLen);
}

export function aes256GcmEncrypt(key, iv, aad, plaintext) {
  if (!_provider || typeof _provider.aes256GcmEncrypt !== "function") throw new Error("aes256GcmEncrypt not available (requires OpenSSL WASM provider)");
  return _provider.aes256GcmEncrypt(key, iv, aad, plaintext);
}

export function aes256GcmDecrypt(key, iv, aad, ciphertext, tag) {
  if (!_provider || typeof _provider.aes256GcmDecrypt !== "function") throw new Error("aes256GcmDecrypt not available (requires OpenSSL WASM provider)");
  return _provider.aes256GcmDecrypt(key, iv, aad, ciphertext, tag);
}