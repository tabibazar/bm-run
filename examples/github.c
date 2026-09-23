/* github.c -- a machine with no operating system asks GitHub about BareMetal,
 * the operating system it is not running. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <curl/curl.h>

__attribute__((weak)) const unsigned char cacert_pem[1];     /* built into every app */
__attribute__((weak)) const unsigned int cacert_pem_len;

static char body[65536];
static size_t got;
static size_t keep(char *p, size_t size, size_t n, void *u) {
	(void)u; size_t len = size * n, room = sizeof body - 1 - got;
	memcpy(body + got, p, len < room ? len : room); got += len < room ? len : room;
	return len;
}
/* The tiniest JSON reader that will do: find "key": and print what follows. */
static void field(const char *key) {
	char pat[64]; snprintf(pat, sizeof pat, "\"%s\":", key);
	char *p = strstr(body, pat);
	if (!p) { printf("%-17s (not found)\n", key); return; }
	p += strlen(pat); while (*p == ' ') p++;
	if (*p == '"') { char *e = strchr(p + 1, '"'); printf("%-17s %.*s\n", key, e ? (int)(e - p - 1) : 0, p + 1); }
	else printf("%-17s %ld\n", key, strtol(p, NULL, 10));
}
int main(void) {
	CURL *h = curl_easy_init();
	struct curl_blob ca = { (void *)cacert_pem, cacert_pem_len, CURL_BLOB_NOCOPY };
	curl_easy_setopt(h, CURLOPT_URL, "https://api.github.com/repos/ReturnInfinity/BareMetal");
	curl_easy_setopt(h, CURLOPT_CAINFO_BLOB, &ca);
	curl_easy_setopt(h, CURLOPT_USERAGENT, "bm-run-example");   /* GitHub requires one */
	curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, keep);
	curl_easy_setopt(h, CURLOPT_TIMEOUT, 30L);
	CURLcode rc = curl_easy_perform(h);
	if (rc != CURLE_OK) { printf("fetch failed: %s\n", curl_easy_strerror(rc)); return 1; }
	long status = 0; curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
	curl_easy_cleanup(h);
	printf("asked api.github.com about ReturnInfinity/BareMetal: HTTP %ld\n\n", status);
	if (status == 403 || status == 429) {
		printf("GitHub's rate limit said no (60 requests an hour per address, and cloud machines share addresses).\nTry again later.\n");
		return 0;
	}
	if (status != 200) return 1;
	field("description"); field("language"); field("stargazers_count"); field("forks_count"); field("created_at");
	return 0;
}
