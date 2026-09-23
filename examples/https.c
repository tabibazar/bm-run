/* https.c -- fetch a web page over TLS, with the server's certificate checked,
 * from a machine with no operating system.
 *
 * libcurl, mbedTLS and the lwIP network stack are linked into every BareMetal
 * app, along with a bundle of CA certificates to verify servers against. */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

/* The CA bundle compiled into every app (see BareMetal-AppPort's curltest.c). */
__attribute__((weak)) const unsigned char cacert_pem[1];
__attribute__((weak)) const unsigned int cacert_pem_len;

static char page[16384];
static size_t got;
static size_t keep(char *p, size_t size, size_t n, void *u) {
	(void)u; size_t len = size * n, room = sizeof page - 1 - got;
	memcpy(page + got, p, len < room ? len : room); got += len < room ? len : room;
	return len;
}
int main(void) {
	CURL *h = curl_easy_init();
	if (!h) { printf("curl_easy_init failed\n"); return 1; }
	struct curl_blob ca = { (void *)cacert_pem, cacert_pem_len, CURL_BLOB_NOCOPY };
	curl_easy_setopt(h, CURLOPT_URL, "https://example.com/");
	curl_easy_setopt(h, CURLOPT_CAINFO_BLOB, &ca);
	curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, 1L);   /* refuse a server we cannot verify */
	curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, 2L);
	curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, keep);
	curl_easy_setopt(h, CURLOPT_TIMEOUT, 30L);
	CURLcode rc = curl_easy_perform(h);
	if (rc != CURLE_OK) { printf("fetch failed: %s\n", curl_easy_strerror(rc)); return 1; }
	long status = 0; curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
	char *t = strstr(page, "<title>"), *e = t ? strstr(t, "</title>") : NULL;
	printf("GET https://example.com/ over verified TLS: HTTP %ld, %zu bytes\n", status, got);
	if (t && e) printf("page title: %.*s\n", (int)(e - t - 7), t + 7);
	curl_easy_cleanup(h);
	return status == 200 ? 0 : 1;
}
