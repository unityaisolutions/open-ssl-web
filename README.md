WebOpenSSL
==========

Web-based OpenSSL-like random key generator that can be loaded as either:
- A minified JavaScript library (dist/webopenssl.min.js)
- With optional WASM provider (compiled OpenSSL via Emscripten) to use RAND_bytes

Purpose
-------
Create random keys similar to `openssl rand -base64 32`, using secure system randomness:
- WebCrypto (browser): `crypto.getRandomValues`, backed by OS CSPRNG
- Node.js (min.js UMD): `crypto.randomBytes`
- Optional OpenSSL WASM module: calls `RAND_bytes` from libcrypto compiled to WebAssembly

This matches OpenSSL's security model for randomness (OS-backed CSPRNG).

Files
-----
- src/index.js (ESM) — readable source
- dist/webopenssl.min.js (UMD) — minified build for browser or Node
- examples/index.html — simple usage in a web page

API
---
- randBytes(length: number): Uint8Array
- randBase64(length: number): string
- randHex(length: number): string
- setProvider(provider: { name: string; randBytes(length): Uint8Array })
- setWasmModule(Module: EmscriptenModule) — configures OpenSSL WASM provider
- getProviderName(): string

Usage (Browser, min.js)
-----------------------
Include the minified UMD bundle:

```html
<script src="./dist/webopenssl.min.js"></script>
<script>
  // Equivalent to: openssl rand -base64 32
  const keyB64 = WebOpenSSL.randBase64(32);
  console.log("base64 key:", keyB64);

  const keyHex = WebOpenSSL.randHex(32);
  console.log("hex key:", keyHex);

  console.log("provider:", WebOpenSSL.getProviderName()); // "webcrypto" (default) or "openssl-wasm" if configured
</script>
```

Usage (ESM)
-----------
```js
import { randBase64, randHex, getProviderName } from "./src/index.js";

console.log(randBase64(32));
console.log(randHex(32));
console.log(getProviderName()); // "webcrypto"
```

Optional: OpenSSL WASM Provider
-------------------------------
If you compile OpenSSL (libcrypto) to WebAssembly using Emscripten and expose `RAND_bytes`, you can configure WebOpenSSL to use it:

Expected module capabilities (Emscripten):
- `cwrap` to wrap C functions
- `_malloc`, `_free` for memory management
- `HEAPU8` to access typed memory views

Example:

```html
<script src="./dist/webopenssl.min.js"></script>
<script src="path/to/your/openssl_module.js"></script>
<script>
  // Assume OpenSSLModuleFactory is emitted by Emscripten build
  OpenSSLModuleFactory().then((Module) => {
    WebOpenSSL.setWasmModule(Module);
    console.log("provider:", WebOpenSSL.getProviderName()); // "openssl-wasm"

    // Generate keys via RAND_bytes through WASM-backed provider
    const key = WebOpenSSL.randBase64(32);
    console.log(key);
  });
</script>
```

Notes on Security
-----------------
- WebOpenSSL uses cryptographically secure randomness:
  - Browser: WebCrypto `getRandomValues` (OS CSPRNG)
  - Node.js: `crypto.randomBytes` (OS CSPRNG)
  - OpenSSL WASM: `RAND_bytes` (OpenSSL's CSPRNG)
- Output length semantics mirror `openssl rand`:
  - `randBase64(n)` generates n random bytes and returns base64 encoding of those bytes.
  - `randHex(n)` generates n random bytes and returns hex encoding.

Limitations
-----------
- This library focuses on secure random key generation. It is not a full re-implementation of OpenSSL.
- For stronger fidelity with OpenSSL internals, integrate the OpenSSL WASM provider as described.

License
-------
MIT