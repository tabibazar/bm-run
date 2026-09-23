# Examples

Every one of these runs as it is. Try them in any order:

```
./bm run examples/hello.c
```

Most finish in about half a second of the machine's life; the rest of the ~30 s is
building and the cloud. Programs marked **checks itself** know the right answer and
say `correct` or `WRONG`, so you can see the machine got it right.

## Start here

| example | what it does |
| --- | --- |
| [hello.c](hello.c) | Prints one line. The smallest possible program. |
| [machine.c](machine.c) | Looks around from the inside: which CPU, what time it is, how much memory it can get, where its code and stack live, and the missing `/etc` where an operating system would be. |

## Pictures in text

| example | what it does |
| --- | --- |
| [mandelbrot.c](mandelbrot.c) | Draws the Mandelbrot set in characters. |
| [life.c](life.c) | Conway's Game of Life: a glider crawls across the grid. **Checks itself**: after 40 generations it must be exactly 10 squares away, same shape. |

## Numbers that check themselves

| example | what it does |
| --- | --- |
| [primes.c](primes.c) | Counts the primes below ten million with a sieve. **Checks itself** against the known count, 664,579. |
| [pi.c](pi.c) | The first 1,000 digits of pi, one at a time, using only integers. **Checks itself** against the known first 100. |
| [collatz.c](collatz.c) | Tests the Collatz conjecture for every number below a million, and finds the longest chain. **Checks itself**: 837,799, with 525 numbers. |
| [threads.c](threads.c) | Four threads on one CPU split a big sum, and share a counter under a mutex. **Checks itself**: the total is n(n+1)/2 and no increment is lost. |

## Libraries that come built in

Every program is linked with SQLite, libsodium, mbedTLS and libcurl, so these need
nothing extra.

| example | what it does |
| --- | --- |
| [database.c](database.c) | A real SQL database in memory, holding the planets. **Checks** Kepler's third law with a query. |
| [crypto.c](crypto.c) | Hashes a message and signs another with libsodium, then changes "10" to "90" and shows the signature fail. **Checks** SHA-256 against the published test vector. |

## The network

| example | what it does |
| --- | --- |
| [https.c](https.c) | Fetches a web page over TLS, with the server's certificate checked. |
| [github.c](github.c) | Asks GitHub's API about BareMetal, the operating system it is not running, and prints its stars and description. GitHub allows 60 unauthenticated requests an hour per address, so this can occasionally be told to wait. |

## Writing your own

Copy any of these and change it. A few things differ from Linux: output is the
serial console, so print results rather than data; there are no command-line
arguments, so put inputs in the source; and when `main` returns, the machine
stops. The main [README](../README.md) has the details.
