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
- scripts/build-openssl-wasm.sh — builds OpenSSL libcrypto to WASM
- src/wasm/openssl_rand_wrapper.c — small wrapper that exposes `openssl_rand_bytes(...)` for Emscripten

API
---
- randBytes(length: number): Uint8Array
- randBase64(length: number): string
- randHex(length: number): string
- setProvider(provider: { name: string; randBytes(length): Uint8Array })
- setWasmModule(Module: EmscriptenModule) — configures OpenSSL WASM provider
- getProviderName(): string
- autoLoadOpenSSLWASM(options?: { url?: string; factoryGlobalName?: string }): Promise<boolean>

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

Auto-load OpenSSL WASM (Browser)
--------------------------------
If you build the OpenSSL WASM module, you can auto-load it:

```html
<script src="./dist/webopenssl.min.js"></script>
<script>
  WebOpenSSL.autoLoadOpenSSLWASM({ url: './dist/openssl-wasm/openssl_module.js' })
    .then((loaded) => {
      console.log("WASM loaded:", loaded);
      console.log("provider:", WebOpenSSL.getProviderName()); // "openssl-wasm" if loaded
    });
</script>
```

Usage (ESM)
-----------
```js
import { randBase64, randHex, getProviderName, autoLoadOpenSSLWASM } from "./src/index.js";

console.log(randBase64(32));
console.log(randHex(32));
console.log(getProviderName()); // "webcrypto"

await autoLoadOpenSSLWASM({ url: "./dist/openssl-wasm/openssl_module.js" });
console.log(getProviderName()); // "openssl-wasm" if loaded
```

Build OpenSSL to WASM (Emscripten)
----------------------------------
Prerequisites:
- macOS/Linux with bash, curl, tar, make, perl
- Emscripten SDK (emsdk) in PATH, or this script will fetch and activate a local copy

Steps:
- Using npm script:
  - npm run build:wasm
- Or directly:
  - bash scripts/build-openssl-wasm.sh

What the script does:
- Downloads OpenSSL 3.5.3
- Builds libcrypto with emconfigure/emmake (disables unsupported features in WASM)
- Compiles a small wrapper (src/wasm/openssl_rand_wrapper.c) and links against libcrypto
- Emits a modularized factory (OpenSSLModuleFactory) at dist/openssl-wasm/openssl_module.js with a .wasm sidecar
- WebOpenSSL can auto-load it via autoLoadOpenSSLWASM or manually via setWasmModule

Manual wiring example
---------------------
```html
<script src="./dist/webopenssl.min.js"></script>
<script src="./dist/openssl-wasm/openssl_module.js"></script>
<script>
  OpenSSLModuleFactory().then((Module) => {
    WebOpenSSL.setWasmModule(Module);
    console.log("provider:", WebOpenSSL.getProviderName()); // "openssl-wasm"
    console.log(WebOpenSSL.randBase64(32));
  });
</script>
```

Notes on Security
-----------------
- WebOpenSSL uses cryptographically secure randomness:
  - Browser: WebCrypto `getRandomValues` (OS CSPRNG)
  - Node.js: `crypto.randomBytes` (OS CSPRNG)
  - OpenSSL WASM: `RAND_bytes` via libcrypto (OpenSSL's CSPRNG)
- Output length semantics mirror `openssl rand`:
  - `randBase64(n)` generates n random bytes and returns base64 encoding of those bytes.
  - `randHex(n)` generates n random bytes and returns hex encoding.

Limitations
-----------
- This library focuses on secure random key generation. It is not a full re-implementation of OpenSSL.
- Building OpenSSL to WASM can be environment-sensitive. The provided script targets modern Emscripten and OpenSSL 3.5.3.

License
-------
MIT