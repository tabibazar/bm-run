# bm run

Run a C program on a unikernel in the cloud, with one command.

```
$ ./bm run examples/hello.c
bm: building examples/hello.c with BareMetal-App
bm: built in 10.1 s: a whole bootable machine of 1,238,104 bytes, sha256 2548a3181f71ef24...
bm: uploading
bm: starting a 1 vCPU, 16 MiB VM
----------------------------------------------------------------- output
Hello from a machine with no operating system.
-------------------------------------------------------------------------
bm: the program ran to completion on BareMetal Cloud, 4.1 s after the VM was created
bm: verified: BareMetal Cloud's own SHA-256 of the image this VM booted matches the one built here (2548a3181f71ef24...)
bm: build 10.1 s, cloud round trip 5.8 s
bm: cleaned up: VM and image deleted
bm: 19 s wall clock, start to finish
```

Your program is compiled into a [BareMetal](https://github.com/ReturnInfinity/BareMetal)
unikernel: the kernel, the C library and your code linked into a single bootable
file of about a megabyte, with no operating system underneath. `bm` uploads it to
[BareMetal Cloud](https://baremetal.returninfinity.com), boots it, waits for it to
finish, prints what it printed, confirms the cloud booted exactly the bytes you
built, and deletes everything it created.

## What you need

- **Docker.** Everything else runs inside a container, so this works the same on
  macOS (including Apple silicon) and Linux.
- **A BareMetal Cloud API key.** Sign in at https://baremetal.returninfinity.com,
  open API keys, create one, and `export BMC_API_KEY=bmc_...`. This is the same
  variable Return Infinity's own `bmcloud` client reads. (`BM_API_KEY`, the name
  earlier versions of `bm` used, still works.) Keys from the BareMetal Cloud alpha,
  which started `bmvps_`, no longer work.

## Quick start

```
git clone https://github.com/tabibazar/bm-run
cd bm-run
./bm setup                 # once: builds the BareMetal toolchain in Docker
export BMC_API_KEY=bmc_...
./bm run examples/hello.c
./bm run examples/mandelbrot.c
./bm run --args "360 1000000007" examples/factor.c
```

There are thirteen examples, from a one-line hello to SQLite, cryptography, threads
and HTTPS. [examples/README.md](examples/README.md) lists them all.

`bm setup` builds the toolchain from source, once. On an Apple M1 Pro, where
Docker emulates x86-64, it took 23 minutes. After that, eight runs of `hello.c` on 5 November 2026
measured:

| stage | median | range |
| --- | --- | --- |
| build (x86-64 emulated on Apple silicon) | 10.0 s | 9.8 to 10.2 s |
| VM created to program finished, as seen from the console | 5.5 s | 3.6 to 5.7 s |
| cloud: upload, boot, wait, fetch the output | 7.1 s | 5.2 to 7.3 s |
| wall clock, start to finish, including cleanup | 20 s | 19 to 21 s |

Most of the wait is building and the cloud's control plane, not the machine. `bm`
checks the console once a second, so the middle figures are accurate to about a
second. On a Linux x86-64 host the build needs no emulation and should be faster.

On the BareMetal Cloud alpha, which this replaced, the same program took 27.5 s
start to finish, 12.0 s of it in the cloud.

## Commands

| command | what it does |
| --- | --- |
| `bm setup` | Clone Return Infinity's [BareMetal-App](https://github.com/ReturnInfinity/BareMetal-App) into a Docker volume and run its own `setup.sh`, which also downloads their `bmcloud` client. Run again to update. |
| `bm run [options] prog.c [more.c ...]` | Build, run in the cloud, print the output, verify, clean up. Several `.c` files link into one program. |
| `bm ls` | Show your plan and limits, and the VMs and images on your account. |
| `bm clean` | Delete every VM and image whose name starts with `bm-`. Leaves everything else alone. |

Options for `bm run`:

| option | what it does |
| --- | --- |
| `--args "A B C"` | Command-line arguments for `main`. They are split on spaces; `argv[0]` is `main`. Up to 150 characters, no backticks. |
| `--ram MiB` | Memory for the machine. The default is 16 MiB, or more if the program is large. Your plan sets the most. |
| `--timeout S` | Stop a program that has not returned after S seconds (default 120). |
| `--keep` | Leave the VM and image on the account afterwards, for looking at in the portal. |

`bm run` exits 0 when the program ran to completion, 1 on an error such as a compile
failure, 3 if the program had to be stopped at the timeout, 4 if the machine stopped
without the program returning (a crash prints a register dump), 5 if the cloud
reports a different image from the one built, and 130 on Ctrl-C. Cleanup runs in
every case.

## Writing programs

Any standard C program with a `main` is a starting point. What is different from
Linux, and worth knowing up front:

- **Output is the serial console.** `printf` works. It moves at about 20 KB a
  second, and the cloud keeps only the most recent ~256 KB: a program that prints
  more shows only its end, and `bm` says so. Print results, not data.
- **The program is the whole machine.** When `main` returns, the machine stops.
  There are no other processes, no `fork`, no shell.
- **Inputs come from `--args`,** or from the source itself.
- **One virtual CPU,** and 16 MiB of memory unless you ask for more with `--ram`.
- **What does work:** `time()`, `malloc`, the usual C library, threads, `RDRAND`
  for randomness, SQLite and libsodium, and the network. libcurl, mbedTLS and the
  lwIP stack are linked into every program with a bundle of CA certificates, so
  `examples/https.c` fetches a page over TLS with the certificate checked. The
  network stack prints a few `net:` lines of its own as it comes up.

`examples/primes.c` shows a habit worth copying: it knows its own right answer and
says whether the machine got it.

## How the verification works

When an image is uploaded, BareMetal Cloud replies with its own SHA-256 of the
bytes it received, and every VM records which image it booted. `bm` checks that the
platform's digest equals the SHA-256 of the file it built, and that the VM it
created names that image. Builds are reproducible: the eight timed builds above
produced the same SHA-256, `2548a3181f71ef24...`. A build depends on the toolchain's
exact versions, which `bm setup` records, so anyone with the source and those
versions can rebuild the image and check the digest themselves.

## How it relates to BareMetal-App

`bm` is a thin wrapper around Return Infinity's own quickstart: their `setup.sh`
builds the toolchain, their `1-build.sh` builds your program, and every call to the
cloud goes through their `bmcloud` client. `bm` adds a container so it runs anywhere
Docker does, and the round trip their `3-upload.sh` leaves to you: waiting for the
program to finish, printing its output, verifying and cleaning up. It redistributes
none of their code; `bm setup` fetches it.

## Testing

```
export BMC_API_KEY=bmc_...
./tests/run.sh
```

Runs twenty-four checks against the real cloud, one VM at a time, in about seven
minutes: all thirteen examples; arguments; `time()`, `RDRAND` and an 8 MiB `malloc`;
a two-file program; a compile error; a missing file; a missing key; a key from the
retired alpha; a program that never returns; a crash; output larger than the
console keeps; and that nothing is left on the account afterwards. All twenty-four
passed on 5 November 2026 against BareMetal-App `c93b2bd`, BareMetal-AppPort
`932f183`, BareMetal-Firecracker `25555eb` and `bmcloud` version 1.

The run before it, on the October toolchain (Firecracker `a7afb53`), passed
twenty-three. `examples/machine.c` crashed with a divide error: looking for
`/etc/os-release` on a VM with no disk tripped the kernel's disk driver. Return
Infinity fixed exactly that on 2 November (`60b8519`, "Fix for DE on no disk"), so
run `bm setup` again if you set up before then.

## Licence

MIT. See [LICENSE](LICENSE).
