#include <openssl/rand.h>
#include <stdint.h>

int openssl_rand_bytes(int ptr, int len) {
    unsigned char *buf = (unsigned char*) (uintptr_t) ptr;
    return RAND_bytes(buf, len);
}