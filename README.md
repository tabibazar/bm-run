# bm run

Run a C program on a unikernel in the cloud, with one command.

```
$ ./bm run examples/hello.c
bm: building examples/hello.c with BareMetal-App
bm: built in 8.7 s: a whole bootable machine of 1,229,232 bytes, sha256 e3e3d84dbc9483b0...
bm: uploading
bm: starting a 1 vCPU, 16 MiB instance
----------------------------------------------------------------- output
Hello from a machine with no operating system.
-------------------------------------------------------------------------
bm: the program ran to completion on BareMetal Cloud (VM alive 0.37 s)
bm: verified: the machine booted exactly the image built here (sha256 e3e3d84dbc9483b0... from the host's boot log)
bm: build 8.7 s, cloud round trip 12.4 s
bm: cleaned up: instance and image deleted
bm: 29 s wall clock, start to finish
```

Your program is compiled into a [BareMetal](https://github.com/ReturnInfinity/BareMetal)
unikernel: the kernel, the C library and your code linked into a single bootable
file of about a megabyte, with no operating system underneath. `bm` uploads it to
[BareMetal Cloud](https://baremetal.returninfinity.com), boots it, waits for it to
finish, prints what it printed, proves the cloud ran exactly the bytes you built,
and deletes everything it created.

## What you need

- **Docker.** Everything else runs inside a container, so this works the same on
  macOS (including Apple silicon) and Linux.
- **A BareMetal Cloud API key.** Sign in at https://baremetal.returninfinity.com,
  open API KEYS, create one, and `export BM_API_KEY=...`.

## Quick start

```
git clone https://github.com/tabibazar/bm-run
cd bm-run
./bm setup                 # once: builds the BareMetal toolchain in Docker
export BM_API_KEY=...
./bm run examples/hello.c
./bm run examples/mandelbrot.c
./bm run examples/database.c   # SQLite, with no operating system underneath
```

There are twelve examples, from a one-line hello to SQLite, cryptography, threads
and HTTPS. [examples/README.md](examples/README.md) lists them all.

`bm setup` builds the toolchain from source, once. On an Apple M1 Pro, where
Docker emulates x86-64, it took 19.5 minutes. After that, eight runs of `hello.c`
measured:

| stage | median | range |
| --- | --- | --- |
| build (x86-64 emulated on Apple silicon) | 8.4 s | 8.3 to 8.7 s |
| cloud: upload, boot, wait, fetch the console | 12.0 s | 11.2 to 16.7 s |
| the virtual machine's entire life, boot to exit | 0.36 s | 0.28 to 0.39 s |
| wall clock, start to finish, including cleanup | 27.5 s | 25 to 33 s |

The machine itself is about one percent of the wait; the rest is building and the
cloud API. On a Linux x86-64 host the build needs no emulation and should be faster.

From a fresh `git clone` of this repository, following this README, the three
examples had all run 20.6 minutes later, 18.8 of them the one-time setup.

Builds are reproducible. The fresh clone's separate toolchain produced images with
the same SHA-256 as the original: `hello.c` is `e3e3d84dbc9483b0...`, `primes.c`
`83a94d9dec2395b9...` and `https.c` `d403ae0776d2b521...`. So when `bm` says the
cloud booted the image with a given hash, anyone can rebuild the source and check
that it is the same machine.

## Commands

| command | what it does |
| --- | --- |
| `bm setup` | Clone Return Infinity's [BareMetal-App](https://github.com/ReturnInfinity/BareMetal-App) into a Docker volume and run its own `setup.sh`. Run again to update. |
| `bm run [--keep] [--timeout S] prog.c [more.c ...]` | Build, run in the cloud, print the output, verify, clean up. Several `.c` files link into one program. `--keep` leaves the instance and image; `--timeout` (default 120) stops a program that does not return. |
| `bm ls` | List the instances and images on your account. |
| `bm clean` | Delete every instance and image whose name starts with `bm-`. Leaves everything else alone. |

`bm run` exits 0 when the program ran to completion, 1 on an error such as a compile
failure, 3 if the program had to be stopped at the timeout, 4 if the machine stopped
without the program returning (a crash prints a register dump), 5 if the machine
booted a different image from the one built, and 130 on Ctrl-C. Cleanup runs in
every case.

## Writing programs

Any standard C program with a `main` is a starting point. What is different from
Linux, and worth knowing up front:

- **Output is the serial console.** `printf` works. It moves at a few kilobytes a
  second, and the cloud keeps only the most recent ~200 KB: a program that prints
  360 KB took 107 s to run and `bm` shows its last 2,216 lines, and says so. Print
  results, not data.
- **The program is the whole machine.** When `main` returns, the machine stops.
  There are no other processes, no `fork`, no shell.
- **No command-line arguments yet.** The cloud's create call takes no parameters, so
  put inputs in the source. Each different input is a different image.
- **16 MiB of memory, one virtual CPU.** Large static arrays count against it.
- **What does work:** `time()`, `malloc`, the usual C library, threads,
  `RDRAND` for randomness, SQLite and libsodium, and the network. libcurl, mbedTLS and the lwIP stack are linked
  into every program with a bundle of CA certificates, so `examples/https.c`
  fetches a page over TLS with the certificate checked. That run's whole machine
  lived 0.94 s, DNS and handshake included. The network stack prints a few
  `net:` lines of its own as it comes up.

`examples/primes.c` shows a habit worth copying: it knows its own right answer and
says whether the machine got it.

## How the verification works

The provider stores each uploaded image under its SHA-256, and the host's Firecracker
log, which arrives in the same console as your output, names that file when the
machine boots. `bm` compares it with the hash of the image it built. The images API
itself returns no digest, so this is the only way today to know which bytes ran.

## How it relates to BareMetal-App

`bm` is a thin wrapper around Return Infinity's own quickstart: their `setup.sh`
builds the toolchain and their `1-build.sh` builds your program. `bm` adds a
container so it runs anywhere Docker does, and the round trip their `3-upload.sh`
leaves to you: waiting, printing the output, verifying and cleaning up. It
redistributes none of their code; `bm setup` clones it from GitHub.

## Testing

```
export BM_API_KEY=...
./tests/run.sh
```

Runs twenty-one checks against the real cloud, one instance at a time, in about
eleven minutes: all twelve examples; `time()`, `RDRAND` and an 8 MiB `malloc`; a
two-file program; a compile error; a missing file; a missing key; a program that
never returns; a crash; output larger than the console keeps; and that nothing is
left on the account afterwards. All twenty-one passed on 23 September 2026 against
BareMetal-App `bb230ef`, BareMetal-AppPort `585f6be` and BareMetal-Firecracker
`a87744e`.

## Licence

MIT. See [LICENSE](LICENSE).
