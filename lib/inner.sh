#!/bin/bash
# inner.sh -- the half of bm that runs inside the container.
#   /work  a Docker volume holding Return Infinity's BareMetal-App toolchain
#   /src   your working directory, read-only
set -euo pipefail
APP=/work/BareMetal-App
say()  { printf 'bm: %s\n' "$*"; }
die()  { printf 'bm: error: %s\n' "$*" >&2; exit 1; }
now()  { date +%s.%N; }
since(){ python3 -c "print(f'{$(now)-$1:.1f}')"; }

setup() {
	local t0; t0=$(now)
	if [ -d "$APP" ]; then say "removing the previous toolchain"; rm -rf "$APP"; fi
	say "cloning ReturnInfinity/BareMetal-App"
	git clone --quiet https://github.com/ReturnInfinity/BareMetal-App "$APP"
	cd "$APP"
	say "running BareMetal-App's own setup.sh (builds musl, lwIP, mbedTLS and the rest; slow under emulation, once only)"
	./setup.sh > /work/setup.log 2>&1 || { tail -40 /work/setup.log >&2; die "setup.sh failed; the full log is /work/setup.log in the $BM_VOLUME volume"; }
	printf '%s\n' "$(git rev-parse --short HEAD)" > /work/.bm-upstream
	( cd BareMetal-AppPort && git rev-parse --short HEAD ) >> /work/.bm-upstream
	( cd BareMetal-Firecracker && git rev-parse --short HEAD ) >> /work/.bm-upstream
	say "toolchain ready in $(since "$t0") s (BareMetal-App $(sed -n 1p /work/.bm-upstream), AppPort $(sed -n 2p /work/.bm-upstream), Firecracker $(sed -n 3p /work/.bm-upstream))"
}

# ---------------------------------------------------------------- run
IMG=""; INST=""; KEEP=0; TIMEDOUT=0
api() { "$APP/bm-api.sh" "$@"; }
field() { awk -F': ' -v k="$1" '$1==k{print $2; exit}'; }

cleanup() {
	[ "$KEEP" = 1 ] && { [ -n "$INST" ] && say "kept instance $INST and image $IMG (--keep)"; return; }
	local ok=1
	if [ -n "$INST" ]; then
		if [ "$(api instances show "$INST" 2>/dev/null | field status)" = RUNNING ]; then
			api instances stop "$INST" >/dev/null 2>&1 || true
		fi
		api instances rm "$INST" >/dev/null 2>&1 || ok=0
	fi
	[ -n "$IMG" ] && { api images rm "$IMG" >/dev/null 2>&1 || ok=0; }
	[ -n "$INST$IMG" ] && { [ "$ok" = 1 ] && say "cleaned up: instance and image deleted" \
		|| say "warning: cleanup incomplete; check 'bm ls' (instance ${INST:-none}, image ${IMG:-none})"; }
}

run() {
	local timeout=120
	while [ $# -gt 0 ]; do
		case "$1" in
			--keep) KEEP=1; shift ;;
			--timeout) timeout="$2"; shift 2 ;;
			--) shift; break ;;
			-*) die "unknown option $1" ;;
			*) break ;;
		esac
	done
	[ $# -ge 1 ] || die "usage: bm run [--keep] [--timeout SECONDS] <program.c> [more.c ...]"
	[ -n "${BM_API_KEY:-}" ] || die "BM_API_KEY is not set. Create a key under API KEYS at https://baremetal.returninfinity.com, then: export BM_API_KEY=..."
	[ -x "$APP/1-build.sh" ] || die "the toolchain is not set up yet: run 'bm setup' first"

	exec 9>/work/.lock; flock 9            # one build at a time per volume
	cd "$APP"
	local job=bmrun-job; rm -rf "$job" "BareMetal-AppPort/$job"; mkdir -p "$job"
	local srcs=() f d
	for f in "$@"; do
		case "$f" in /*|../*|*/../*) die "$f: give a path inside the current directory" ;; esac
		[ -f "/src/$f" ] || die "$f not found in the current directory"
		d="$job/$(dirname "$f")"; mkdir -p "$d"; cp "/src/$f" "$d/"
		for h in "/src/$(dirname "$f")"/*.h; do [ -f "$h" ] && cp "$h" "$d/"; done
		srcs+=("$job/$f")
	done
	local name; name="$(basename "$1")"; name="${name%.*}"
	name="bm-$(printf '%s' "$name" | tr -c 'A-Za-z0-9-' '-' | cut -c1-40)"

	# room on the account? stopped instances count toward the cap. Checked
	# before building, so a full account costs nothing.
	local ninst nimg
	ninst=$(api instances list | grep -c . || true); nimg=$(api images list | grep -c $'\tyours$' || true)
	[ "$ninst" -lt 4 ] || die "your account already has $ninst instances and the cap is 4 (stopped ones count). 'bm clean' removes the ones bm made; 'bm ls' lists everything"
	[ "$nimg" -lt 10 ] || die "your account already has $nimg images and the cap is 10. 'bm clean' removes the ones bm made; 'bm ls' lists everything"

	# 1. build, with Return Infinity's own pipeline
	local t0 tb; t0=$(now)
	say "building $* with BareMetal-App"
	./1-build.sh "${srcs[@]}" > /tmp/build.log 2>&1 || { grep -v '^Building\.\.\.$' /tmp/build.log | sed "s#$job/##g" | tail -30 >&2; die "build failed (compiler output above)"; }
	tb=$(since "$t0")
	local elf=BareMetal-Firecracker/sys/baremetal.elf sha size
	[ -f "$elf" ] || die "build finished but $elf was not produced"
	sha=$(sha256sum "$elf" | cut -c1-64); size=$(stat -c %s "$elf")
	say "built in $tb s: a whole bootable machine of $(python3 -c "print(f'{$size:,}')") bytes, sha256 ${sha:0:16}..."


	# 2. upload. The id is taken from the difference between the image list
	#    before and after, because an upload can report an error and still land.
	trap cleanup EXIT
	trap 'say "interrupted"; exit 130' INT TERM   # PID 1 ignores signals without a handler
	local before after tu; before=$(api images list | cut -f1 | sort); tu=$(now)
	say "uploading"
	IMG=$(api images upload "$name" "$elf" 2>/dev/null | field id) || true
	if [ -z "$IMG" ]; then
		after=$(api images list | cut -f1 | sort)
		IMG=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
		[ -n "$IMG" ] || die "upload failed"
		say "the upload reported an error but the image arrived; continuing with $IMG"
	fi

	# 3. boot it
	say "starting a 1 vCPU, 16 MiB instance"
	INST=$(api instances create "$name" 1 16 "$IMG" 2>/dev/null | field id) || true
	[ -n "$INST" ] || die "could not create an instance"
	local tr st booted=""; tr=$(now)
	# Read the console once right away: the boot log naming the image's sha256
	# is at the top, and a program with a lot of output can push it out of the
	# window the cloud keeps.
	booted=$( { api instances logs "$INST" 2>/dev/null || true; } | { grep -o 'user-images/[0-9a-f]\{64\}' || true; } | head -1 | cut -d/ -f2)
	while :; do
		st=$(api instances show "$INST" 2>/dev/null | field status || true)
		[ "$st" = STOPPED ] && break
		if python3 -c "import sys; sys.exit(0 if $(now)-$tr > $timeout else 1)"; then
			say "still running after $timeout s; stopping it (use --timeout to allow longer)"
			api instances stop "$INST" >/dev/null 2>&1 || true; TIMEDOUT=1; break
		fi
		sleep 2
	done

	# 4. read the console, and verify which image actually booted
	api instances logs "$INST" 2>/tmp/logs.err | tr -d '\r' > /tmp/console.txt || true
	[ -n "$booted" ] || booted=$( { grep -o 'user-images/[0-9a-f]\{64\}' /tmp/console.txt || true; } | head -1 | cut -d/ -f2)
	local truncated=0; grep -q 'most recent portion' /tmp/logs.err 2>/dev/null && truncated=1
	echo "----------------------------------------------------------------- output"
	if grep -q 'Starting Payload' /tmp/console.txt; then
		awk '/Starting Payload/{on=1; getline; next} /^=+$/ && on {next} /Finished Payload/{exit} /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/ {next} on' /tmp/console.txt | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' 
	else
		{ grep -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T|^=+$|Finished Payload' /tmp/console.txt || true; } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
	fi
	echo "-------------------------------------------------------------------------"
	local guest; guest=$(python3 - /tmp/console.txt <<'PYEOF'
import re, sys, datetime
ts=[l[:26] for l in open(sys.argv[1]) if re.match(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+', l)]
if len(ts) >= 2:
    f=lambda s: datetime.datetime.fromisoformat(s)
    print(f"{(f(ts[-1])-f(ts[0])).total_seconds():.2f}")
PYEOF
)
	local rc=0
	[ "$truncated" = 1 ] && say "the output was longer than the cloud keeps, so only its end is shown above (print less, or summarise)"
	[ "$truncated" = 1 ] && guest=""
	if grep -q 'Finished Payload' /tmp/console.txt; then
		say "the program ran to completion on BareMetal Cloud${guest:+ (VM alive $guest s)}"
	elif [ "$TIMEDOUT" = 1 ]; then
		say "the program did not return within $timeout s, so bm stopped it"; rc=3
	else
		say "the machine stopped without the program returning normally (it may have crashed)"; rc=4
	fi
	if [ -z "$booted" ]; then
		say "could not find the booted image's digest in the console, so it is unverified"
	elif [ "$booted" = "$sha" ]; then
		say "verified: the machine booted exactly the image built here (sha256 ${sha:0:16}... from the host's boot log)"
	else
		say "WARNING: the machine booted ${booted:0:16}..., not the image built here (${sha:0:16}...)"; rc=5
	fi
	say "build $tb s, cloud round trip $(since "$tu") s"
	return $rc
}

clean() {
	cd "$APP"
	local n=0 id name st
	while IFS=$'\t' read -r id name st; do
		case "$name" in bm-*) ;; *) continue ;; esac
		[ "$st" = RUNNING ] && api instances stop "$id" >/dev/null 2>&1 || true
		api instances rm "$id" >/dev/null 2>&1 && { say "deleted instance $name ($id)"; n=$((n+1)); } || say "could not delete instance $id"
	done < <(api instances list)
	while IFS=$'\t' read -r id name who; do
		[ "$who" = yours ] || continue
		case "$name" in bm-*) ;; *) continue ;; esac
		api images rm "$id" >/dev/null 2>&1 && { say "deleted image $name ($id)"; n=$((n+1)); } || say "could not delete image $id"
	done < <(api images list)
	say "removed $n item(s); anything not named bm-* was left alone"
}

case "${1:-}" in
	setup) shift; setup "$@" ;;
	run) shift; run "$@" ;;
	clean) [ -n "${BM_API_KEY:-}" ] || die "BM_API_KEY is not set"; clean ;;
	ls) cd "$APP"; echo "instances:"; api instances list; echo "images:"; api images list | grep $'\tyours$' || true ;;
	*) die "unknown inner command '${1:-}'" ;;
esac
