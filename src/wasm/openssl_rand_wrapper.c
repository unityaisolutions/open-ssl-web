#include <openssl/rand.h>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <stdint.h>

/* Random bytes via OpenSSL RAND_bytes */
int openssl_rand_bytes(int ptr, int len) {
    unsigned char *buf = (unsigned char*) (uintptr_t) ptr;
    return RAND_bytes(buf, len);
}

/* PBKDF2-HMAC-SHA256 */
int pbkdf2_hmac_sha256(int pass_ptr, int pass_len,
                       int salt_ptr, int salt_len,
                       int iterations,
                       int out_ptr, int out_len) {
    const unsigned char *pass = (const unsigned char*)(uintptr_t) pass_ptr;
    const unsigned char *salt = (const unsigned char*)(uintptr_t) salt_ptr;
    unsigned char *out = (unsigned char*)(uintptr_t) out_ptr;
    if (out_len <= 0 || iterations <= 0) return 0;
    return PKCS5_PBKDF2_HMAC((const char*)pass, pass_len, salt, salt_len, iterations,
                             EVP_sha256(), out_len, out);
}

/* PBKDF2-HMAC-SHA512 */
int pbkdf2_hmac_sha512(int pass_ptr, int pass_len,
                       int salt_ptr, int salt_len,
                       int iterations,
                       int out_ptr, int out_len) {
    const unsigned char *pass = (const unsigned char*)(uintptr_t) pass_ptr;
    const unsigned char *salt = (const unsigned char*)(uintptr_t) salt_ptr;
    unsigned char *out = (unsigned char*)(uintptr_t) out_ptr;
    if (out_len <= 0 || iterations <= 0) return 0;
    return PKCS5_PBKDF2_HMAC((const char*)pass, pass_len, salt, salt_len, iterations,
                             EVP_sha512(), out_len, out);
}

/* SHA-256 digest (32 bytes) */
int sha256_digest(int data_ptr, int data_len, int out_ptr) {
    const unsigned char *data = (const unsigned char*)(uintptr_t) data_ptr;
    unsigned char *out = (unsigned char*)(uintptr_t) out_ptr;
    unsigned char *ret = SHA256(data, (size_t)data_len, out);
    return ret != NULL ? 1 : 0;
}

/* SHA-512 digest (64 bytes) */
int sha512_digest(int data_ptr, int data_len, int out_ptr) {
    const unsigned char *data = (const unsigned char*)(uintptr_t) data_ptr;
    unsigned char *out = (unsigned char*)(uintptr_t) out_ptr;
    unsigned char *ret = SHA512(data, (size_t)data_len, out);
    return ret != NULL ? 1 : 0;
}

/* AES-256-GCM encrypt
 * Inputs:
 *  - key_ptr: 32-byte key
 *  - iv_ptr / iv_len: IV (recommended 12 bytes)
 *  - aad_ptr / aad_len: optional AAD (can be 0-length)
 *  - plaintext_ptr / plaintext_len: plaintext to encrypt
 * Outputs:
 *  - ciphertext_ptr: buffer to receive ciphertext (size >= plaintext_len + 16)
 *  - tag_ptr: buffer to receive 16-byte authentication tag
 * Returns: ciphertext length on success, -1 on failure
 */
int aes_256_gcm_encrypt(int key_ptr,
                        int iv_ptr, int iv_len,
                        int aad_ptr, int aad_len,
                        int plaintext_ptr, int plaintext_len,
                        int ciphertext_ptr,
                        int tag_ptr) {
    const unsigned char *key = (const unsigned char*)(uintptr_t) key_ptr;
    const unsigned char *iv = (const unsigned char*)(uintptr_t) iv_ptr;
    const unsigned char *aad = (const unsigned char*)(uintptr_t) aad_ptr;
    const unsigned char *plaintext = (const unsigned char*)(uintptr_t) plaintext_ptr;
    unsigned char *ciphertext = (unsigned char*)(uintptr_t) ciphertext_ptr;
    unsigned char *tag = (unsigned char*)(uintptr_t) tag_ptr;

    int len = 0;
    int ciphertext_len = 0;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv_len, NULL) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }

    if (aad && aad_len > 0) {
        if (EVP_EncryptUpdate(ctx, NULL, &len, aad, aad_len) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    }

    if (EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, plaintext_len) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    ciphertext_len = len;

    if (EVP_EncryptFinal_ex(ctx, ciphertext + ciphertext_len, &len) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    ciphertext_len += len;

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }

    EVP_CIPHER_CTX_free(ctx);
    return ciphertext_len;
}

/* AES-256-GCM decrypt
 * Inputs:
 *  - key_ptr: 32-byte key
 *  - iv_ptr / iv_len: IV (recommended 12 bytes)
 *  - aad_ptr / aad_len: optional AAD (can be 0-length)
 *  - ciphertext_ptr / ciphertext_len: ciphertext to decrypt
 *  - tag_ptr: 16-byte authentication tag
 * Output:
 *  - plaintext_ptr: buffer to receive plaintext (size >= ciphertext_len)
 * Returns: plaintext length on success, -1 on failure (including tag verification failure)
 */
int aes_256_gcm_decrypt(int key_ptr,
                        int iv_ptr, int iv_len,
                        int aad_ptr, int aad_len,
                        int ciphertext_ptr, int ciphertext_len,
                        int tag_ptr,
                        int plaintext_ptr) {
    const unsigned char *key = (const unsigned char*)(uintptr_t) key_ptr;
    const unsigned char *iv = (const unsigned char*)(uintptr_t) iv_ptr;
    const unsigned char *aad = (const unsigned char*)(uintptr_t) aad_ptr;
    const unsigned char *ciphertext = (const unsigned char*)(uintptr_t) ciphertext_ptr;
    const unsigned char *tag = (const unsigned char*)(uintptr_t) tag_ptr;
    unsigned char *plaintext = (unsigned char*)(uintptr_t) plaintext_ptr;

    int len = 0;
    int plaintext_len = 0;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv_len, NULL) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }

    if (aad && aad_len > 0) {
        if (EVP_DecryptUpdate(ctx, NULL, &len, aad, aad_len) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    }

    if (EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, ciphertext_len) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }
    plaintext_len = len;

    /* Set expected tag before finalizing */
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, (void*)tag) != 1) { EVP_CIPHER_CTX_free(ctx); return -1; }

    if (EVP_DecryptFinal_ex(ctx, plaintext + plaintext_len, &len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    plaintext_len += len;

    EVP_CIPHER_CTX_free(ctx);
    return plaintext_len;
}