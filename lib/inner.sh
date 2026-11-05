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
	[ -x bmcloud ] || die "setup.sh did not download the bmcloud client"
	printf 'bmcloud v%s\n' "$(sed -n 's/^VERSION=//p' bmcloud)" >> /work/.bm-upstream
	say "toolchain ready in $(since "$t0") s (BareMetal-App $(sed -n 1p /work/.bm-upstream), AppPort $(sed -n 2p /work/.bm-upstream), Firecracker $(sed -n 3p /work/.bm-upstream), $(sed -n 4p /work/.bm-upstream))"
}

# ---------------------------------------------------------------- cloud
# Every call to BareMetal Cloud goes through bmcloud, Return Infinity's own
# command-line client, which their setup.sh downloads into the toolchain.
# bc leaves the JSON reply in /tmp/api.out; bcerr is bmcloud's error message.
BMCLOUD="$APP/bmcloud"
export BMC_API_KEY="${BMC_API_KEY:-${BM_API_KEY:-}}"
bc()    { "$BMCLOUD" --json "$@" > /tmp/api.out 2> /tmp/bc.err; }
bcerr() { sed 's/^bmcloud: //' /tmp/bc.err | tail -1; }
j()     { jq -r "$1" /tmp/api.out; }

check_key() {
	[ -n "$BMC_API_KEY" ] || die "BMC_API_KEY is not set. Create a key under API keys at https://baremetal.returninfinity.com, then: export BMC_API_KEY=bmc_..."
	case "$BMC_API_KEY" in bmvps_*) die "that is a key for the BareMetal Cloud alpha, which has been replaced. Create a new key (it starts bmc_) under API keys at https://baremetal.returninfinity.com" ;; esac
	[ -x "$BMCLOUD" ] || die "this toolchain predates the bmcloud client: run 'bm setup' again"
	bc whoami || die "BareMetal Cloud refused the API key: $(bcerr)"
}

# ---------------------------------------------------------------- run
IMG=""; VM=""; KEEP=0

cleanup() {
	if [ "$KEEP" = 1 ]; then [ -n "$VM" ] && say "kept VM $VM and image $IMG (--keep); 'bm clean' removes them"; return; fi
	local okd=1 i d
	if [ -n "$VM" ]; then bc vm delete "$VM" --yes || okd=0; fi
	if [ -n "$IMG" ]; then
		d=0; for i in 1 2 3 4 5; do bc image delete "$IMG" --yes && { d=1; break; }; sleep 2; done   # waits for the VM to let go
		[ "$d" = 1 ] || okd=0
	fi
	[ -n "$VM$IMG" ] && { [ "$okd" = 1 ] && say "cleaned up: VM and image deleted" \
		|| say "warning: cleanup incomplete; run 'bm clean' (VM ${VM:-none}, image ${IMG:-none})"; }
}

# the newest 256 KB of the VM's console, into /tmp/console.txt; a failed
# fetch keeps the previous copy
console() {
	"$BMCLOUD" vm console "$VM" --bytes 262144 2>/tmp/bc.err | tr -d '\r' > /tmp/console.new && mv /tmp/console.new /tmp/console.txt || true
}

# the first run of the program in the console: between the first payload
# markers, without the platform's own [bm-node] lines
first_run() {
	awk '/Starting Payload/ && !seen {on=1; seen=1; getline; next}
	     /Finished Payload/ && on {exit}
	     /^\[bm-node\]/ {if (on) exit; next}
	     /^=+$/ {next}
	     on' /tmp/console.txt | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

run() {
	local timeout=120 args="" ram=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--keep) KEEP=1; shift ;;
			--timeout) timeout="$2"; shift 2 ;;
			--args) args="$2"; shift 2 ;;
			--ram) ram="$2"; shift 2 ;;
			--) shift; break ;;
			-*) die "unknown option $1" ;;
			*) break ;;
		esac
	done
	[ $# -ge 1 ] || die "usage: bm run [--args \"A B C\"] [--ram MiB] [--timeout S] [--keep] <program.c> [more.c ...]"
	case "$args" in *'`'*) die "--args cannot contain a backtick" ;; esac
	[ ${#args} -le 150 ] || die "--args is ${#args} characters; it has to fit in the machine's 256-byte boot command line, so keep it under 150"
	[ -x "$APP/1-build.sh" ] || die "the toolchain is not set up yet: run 'bm setup' first"
	check_key
	local max_vms max_img max_ram nvm nimg
	max_vms=$(j .limits.max_vms); max_img=$(j .limits.max_images); max_ram=$(j .limits.max_ram_mib)

	# room on the account? Checked before building, so a full account costs nothing.
	bc vm list || die "could not list VMs: $(bcerr)"; nvm=$(j '.vms | length')
	bc image list || die "could not list images: $(bcerr)"; nimg=$(j '.images | length')
	[ "$nvm" -lt "$max_vms" ] || die "your account already has $nvm VM(s) and your plan allows $max_vms. 'bm clean' removes the ones bm made; 'bm ls' lists everything"
	[ "$nimg" -lt "$max_img" ] || die "your account already has $nimg image(s) and your plan allows $max_img. 'bm clean' removes the ones bm made; 'bm ls' lists everything"

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
	name="bm-$(printf '%s' "$name" | tr -c 'A-Za-z0-9-' '-' | cut -c1-37)"

	# 1. build, with Return Infinity's own pipeline
	local t0 tb; t0=$(now)
	say "building $* with BareMetal-App"
	./1-build.sh "${srcs[@]}" > /tmp/build.log 2>&1 || { grep -av '^Building\.\.\.$' /tmp/build.log | sed "s#$job/##g" | tail -30 >&2; die "build failed (compiler output above)"; }
	tb=$(since "$t0")
	local elf=BareMetal-Firecracker/sys/baremetal.elf sha size minram
	[ -f "$elf" ] || die "build finished but $elf was not produced"
	sha=$(sha256sum "$elf" | cut -c1-64); size=$(stat -c %s "$elf")
	say "built in $tb s: a whole bootable machine of $(python3 -c "print(f'{$size:,}')") bytes, sha256 ${sha:0:16}..."
	minram=$(( (size + 1048575) / 1048576 + 2 )); [ "$minram" -ge 4 ] || minram=4
	[ -n "$ram" ] || { ram=16; [ "$ram" -ge "$minram" ] || ram=$minram; }
	[ "$ram" -ge "$minram" ] || die "--ram $ram is too small for a ${size}-byte image; it needs at least $minram MiB"
	[ "$ram" -le "$max_ram" ] || die "$ram MiB is more than your plan allows per VM ($max_ram MiB)"

	trap cleanup EXIT
	trap 'say "interrupted"; exit 130' INT TERM   # PID 1 ignores signals without a handler

	# 2. upload. If the reply is lost, find the image by its digest instead.
	local tu rsha; tu=$(now)
	say "uploading"
	if bc image upload "$elf" --name "$name" --kind kernel; then IMG=$(j .image.id); rsha=$(j .image.sha256)
	else
		local e; e=$(bcerr)
		bc image list || true
		IMG=$(jq -r --arg s "$sha" '[.images[]? | select(.sha256 == $s)][0].id // empty' /tmp/api.out 2>/dev/null || true)
		[ -n "$IMG" ] || die "upload failed${e:+: $e}"
		rsha=$sha; say "the upload reported an error but the image arrived; continuing with $IMG"
	fi

	# 3. boot it
	say "starting a 1 vCPU, $ram MiB VM${args:+ with arguments: $args}"
	bc vm create "$name" --kernel "$IMG" --ram "$ram" --disk none --args "$args" --no-https || die "could not create a VM: $(bcerr)"
	VM=$(j .vm.id); local vimg; vimg=$(j .vm.kernel_image_id)

	# 4. wait. The console shows the end of the program within a second or two;
	#    the VM's status takes up to ~30 s to catch up, so the console decides.
	local tr outcome="" st des n=0; tr=$(now)
	while :; do
		console
		if grep -aq 'Finished Payload' /tmp/console.txt 2>/dev/null; then outcome=finished; break; fi
		if grep -aq 'Exception 0x' /tmp/console.txt 2>/dev/null; then sleep 1; console; outcome=crashed; break; fi
		n=$((n+1))
		if [ $((n % 3)) = 0 ] && bc vm show "$VM"; then
			st=$(j .vm.status); des=$(j .vm.desired)
			[ "$st" = stopped ] && [ "$des" = stopped ] && { outcome=stopped; break; }
		fi
		python3 -c "import sys; sys.exit(0 if $(now)-$tr > $timeout else 1)" && { outcome=timeout; break; }
		sleep 1
	done
	local tdone; tdone=$(since "$tr")

	# 5. show it, and say what the platform vouches for
	echo "----------------------------------------------------------------- output"
	if grep -aq 'Starting Payload' /tmp/console.txt; then first_run
	else
		{ grep -av -E '^\[bm-node\]|^=+$|Finished Payload' /tmp/console.txt || true; } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
	fi
	echo "-------------------------------------------------------------------------"
	local rc=0
	if [ "$outcome" = finished ] && ! grep -aq 'Starting Payload' /tmp/console.txt; then
		say "the output was longer than the console keeps, so only its end is shown above (print less, or summarise)"
	fi
	case "$outcome" in
		finished) say "the program ran to completion on BareMetal Cloud, ${tdone} s after the VM was created" ;;
		timeout)  say "the program did not return within $timeout s, so bm stopped it"; rc=3 ;;
		crashed|stopped) say "the machine stopped without the program returning normally (it may have crashed)"; rc=4 ;;
	esac
	if [ "$rsha" = "$sha" ] && [ "$vimg" = "$IMG" ]; then
		say "verified: BareMetal Cloud's own SHA-256 of the image this VM booted matches the one built here (${sha:0:16}...)"
	else
		say "WARNING: the platform reports image ${rsha:0:16}... but the image built here is ${sha:0:16}..."; rc=5
	fi
	say "build $tb s, cloud round trip $(since "$tu") s"
	return $rc
}

ls_() {
	check_key
	echo "plan: $(j .user.plan) ($(j .limits.max_vms) VMs, $(j .limits.max_images) images, up to $(j .limits.max_ram_mib) MiB a VM)"
	bc vm list    || die "$(bcerr)"; echo "VMs:";    j '.vms[]    | "  \(.id)\t\(.name)\t\(.status)"'
	bc image list || die "$(bcerr)"; echo "images:"; j '.images[] | "  \(.id)\t\(.name)\t\(.kind)\t\(.size_bytes) bytes\tsha256 \(.sha256[0:16])..."'
}

clean() {
	check_key
	local n=0 id i d vms imgs
	bc vm list || die "$(bcerr)"; vms=$(j '.vms[] | select(.name | startswith("bm-")) | .id')
	for id in $vms; do
		bc vm delete "$id" --yes && { say "deleted VM $id"; n=$((n+1)); } || say "could not delete VM $id: $(bcerr)"
	done
	bc image list || die "$(bcerr)"; imgs=$(j '.images[] | select(.name | startswith("bm-")) | .id')
	for id in $imgs; do
		d=0; for i in 1 2 3 4 5; do bc image delete "$id" --yes && { d=1; break; }; sleep 2; done
		[ "$d" = 1 ] && { say "deleted image $id"; n=$((n+1)); } || say "could not delete image $id: $(bcerr)"
	done
	say "removed $n item(s); anything not named bm-* was left alone"
}

case "${1:-}" in
	setup) shift; setup "$@" ;;
	run) shift; run "$@" ;;
	clean) clean ;;
	ls) ls_ ;;
	*) die "unknown inner command '${1:-}'" ;;
esac
