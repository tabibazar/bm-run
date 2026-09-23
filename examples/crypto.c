/* crypto.c -- cryptography from libsodium, which is built into every program.
 * Hash a message, then sign one and show that a single changed letter makes
 * the signature fail. */
#include <stdio.h>
#include <string.h>
#include <sodium.h>

static void hex(const unsigned char *p, size_t n) { for (size_t i = 0; i < n; i++) printf("%02x", p[i]); }

int main(void) {
	if (sodium_init() < 0) { printf("libsodium failed to start\n"); return 1; }
	int ok = 1;

	/* SHA-256 of "abc", against the value in the standard (FIPS 180-4). */
	unsigned char h[crypto_hash_sha256_BYTES];
	crypto_hash_sha256(h, (const unsigned char *)"abc", 3);
	static const unsigned char want[32] = {
		0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
		0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad };
	printf("SHA-256(\"abc\") = "); hex(h, 32);
	printf("\n                 %s\n\n", memcmp(h, want, 32) == 0 ? "matches the published test vector" : "DOES NOT MATCH");
	ok &= memcmp(h, want, 32) == 0;

	/* An Ed25519 signature: a fresh key pair, from the CPU's random numbers. */
	unsigned char pk[crypto_sign_PUBLICKEYBYTES], sk[crypto_sign_SECRETKEYBYTES], sig[crypto_sign_BYTES];
	crypto_sign_keypair(pk, sk);
	char msg[] = "Pay Alice 10 dollars";
	crypto_sign_detached(sig, NULL, (unsigned char *)msg, strlen(msg), sk);
	printf("public key      "); hex(pk, 16); printf("...\n");
	printf("signed          \"%s\"\n", msg);
	int good = crypto_sign_verify_detached(sig, (unsigned char *)msg, strlen(msg), pk) == 0;
	printf("verify          %s\n", good ? "valid" : "INVALID");
	msg[10] = '9';                                  /* "10" becomes "90" */
	int forged = crypto_sign_verify_detached(sig, (unsigned char *)msg, strlen(msg), pk) == 0;
	printf("tampered        \"%s\"  %s\n", msg, forged ? "STILL VALID" : "rejected");
	ok &= good && !forged;

	printf("\n%s\n", ok ? "correct: hashing matches the standard, and a forged message is caught" : "SOMETHING FAILED");
	return !ok;
}
