# Informal benchmarks and commentary

# Comparative benchmarks

The slowest operations in this program are:

1. Reading from the file system
2. Allocating memory
3. Copying memory

And the actual parsing logic is a very distant fourth. So, we shuold expect programs that minimize those three operations to be the fastest.

## Rust

[rust-csv](https://github.com/BurntSushi/rust-csv) has some great benchmarks and it was my main reference. Running `cargo bench` directly:

```sh
$ cargo bench

   Compiling csv v1.2.2 (/Users/bensu/dev/rust/rust-csv)
    Finished bench [optimized + debuginfo] target(s) in 2.44s
     Running benches/bench.rs (target/release/deps/bench-6c982cc063c13222)

running 44 tests
test count_game_deserialize_borrowed_bytes ... bench:   8,065,870 ns/iter (+/- 233,583) = 322 MB/s
test count_game_deserialize_borrowed_str   ... bench:   6,960,295 ns/iter (+/- 243,340) = 373 MB/s
test count_game_deserialize_owned_bytes    ... bench:  16,093,475 ns/iter (+/- 301,209) = 161 MB/s
test count_game_deserialize_owned_str      ... bench:  14,882,358 ns/iter (+/- 402,950) = 174 MB/s <--
test count_game_iter_bytes                 ... bench:   9,494,508 ns/iter (+/- 338,213) = 273 MB/s
test count_game_iter_str                   ... bench:   9,898,333 ns/iter (+/- 198,424) = 262 MB/s
test count_game_read_bytes                 ... bench:   4,242,995 ns/iter (+/- 43,985)  = 612 MB/s
test count_game_read_str                   ... bench:   4,709,004 ns/iter (+/- 57,537)  = 552 MB/s
test count_mbta_deserialize_borrowed_bytes ... bench:   1,723,945 ns/iter (+/- 22,063)  = 419 MB/s
test count_mbta_deserialize_borrowed_str   ... bench:   1,296,791 ns/iter (+/- 35,429)  = 557 MB/s
test count_mbta_deserialize_owned_bytes    ... bench:   2,438,525 ns/iter (+/- 36,417)  = 296 MB/s
test count_mbta_deserialize_owned_str      ... bench:   2,466,441 ns/iter (+/- 51,486)  = 293 MB/s
test count_mbta_iter_bytes                 ... bench:   1,462,233 ns/iter (+/- 75,886)  = 494 MB/s
test count_mbta_iter_str                   ... bench:   1,505,191 ns/iter (+/- 40,657)  = 480 MB/s
test count_mbta_read_bytes                 ... bench:     831,699 ns/iter (+/- 11,314)  = 869 MB/s
test count_mbta_read_str                   ... bench:     899,329 ns/iter (+/- 17,562)  = 804 MB/s
test count_nfl_deserialize_borrowed_bytes  ... bench:   2,962,145 ns/iter (+/- 58,044)  = 460 MB/s
test count_nfl_deserialize_borrowed_str    ... bench:   2,390,412 ns/iter (+/- 55,392)  = 570 MB/s  <--
test count_nfl_deserialize_owned_bytes     ... bench:   3,716,087 ns/iter (+/- 176,103) = 367 MB/s
test count_nfl_deserialize_owned_str       ... bench:   3,824,187 ns/iter (+/- 141,876) = 356 MB/s
test count_nfl_iter_bytes                  ... bench:   1,913,249 ns/iter (+/- 29,883)  = 713 MB/s
test count_nfl_iter_bytes_trimmed          ... bench:   3,757,229 ns/iter (+/- 34,326)  = 363 MB/s
test count_nfl_iter_str                    ... bench:   1,988,150 ns/iter (+/- 17,114)  = 686 MB/s
test count_nfl_iter_str_trimmed            ... bench:   5,465,308 ns/iter (+/- 165,054) = 249 MB/s
test count_nfl_read_bytes                  ... bench:   1,269,137 ns/iter (+/- 49,243)  = 1075 MB/s
test count_nfl_read_str                    ... bench:   1,476,116 ns/iter (+/- 48,518)  = 924 MB/s
test count_pop_deserialize_borrowed_bytes  ... bench:   3,333,231 ns/iter (+/- 125,437) = 286 MB/s
test count_pop_deserialize_borrowed_str    ... bench:   2,758,070 ns/iter (+/- 98,679)  = 346 MB/s
test count_pop_deserialize_owned_bytes     ... bench:   4,632,137 ns/iter (+/- 180,449) = 206 MB/s
test count_pop_deserialize_owned_str       ... bench:   4,693,458 ns/iter (+/- 181,373) = 203 MB/s
test count_pop_iter_bytes                  ... bench:   2,627,319 ns/iter (+/- 109,542) = 363 MB/s
test count_pop_iter_str                    ... bench:   2,907,429 ns/iter (+/- 227,163) = 328 MB/s
test count_pop_read_bytes                  ... bench:   1,294,604 ns/iter (+/- 62,077)  = 738 MB/s
test count_pop_read_str                    ... bench:   1,614,260 ns/iter (+/- 97,181)  = 592 MB/s

test count_pop_serialize_owned_bytes       ... bench:   3,154,674 ns/iter (+/- 126,790) = 302 MB/s
test count_pop_serialize_owned_str         ... bench:   3,166,389 ns/iter (+/- 109,904) = 301 MB/s
test count_nfl_serialize_owned_bytes       ... bench:   1,750,929 ns/iter (+/- 52,025)  = 779 MB/s
test count_nfl_serialize_owned_str         ... bench:   1,747,004 ns/iter (+/- 66,797)  = 781 MB/s
test write_nfl_bytes                       ... bench:   1,327,003 ns/iter (+/- 146,721) = 1028 MB/s
test write_nfl_record                      ... bench:   1,564,508 ns/iter (+/- 170,333) = 872 MB/s
test count_mbta_serialize_owned_bytes      ... bench:   1,015,004 ns/iter (+/- 6,758)   = 614 MB/s
test count_mbta_serialize_owned_str        ... bench:   1,017,125 ns/iter (+/- 12,469)  = 612 MB/s
test count_game_serialize_owned_bytes      ... bench:   6,028,716 ns/iter (+/- 177,371) = 364 MB/s
test count_game_serialize_owned_str        ... bench:   6,022,525 ns/iter (+/- 74,155)  = 365 MB/s
```

The relevant benchmarks for deserialization are:

- `*_deserialize_borrowed_bytes`
- `*_deserialize_borrowed_str`
- `*_deserialize_owned_bytes`
- `*_deserialize_owned_str`

where `owned` is slower than `borrowed` because it has additional allocations and `str` is slower than `bytes` because it does UTF-8 validation.

They vary between 174 MB/s and 570 MB/s. zig library ends up in a very similar range, between 325 MB/s and 598 MB/s using the same `nfl` and `pop`, and `mbta` files:

```sh
$ zig build -Drelease-fast=true; zig-out/bin/csv

Starting benchmark
Parsed in 4ms on average     -- bench.NFL               // 1.3MB all columns, 325 MB/s <-- nfl
Parsed in 418ms on average   -- bench.FullPopulation    // 144MB all columns, 344 MB/s <-- pop
Parsed in 301ms on average   -- bench.Population        // 144MB few columns, 478 MB/s
Parsed in 1ms on average     -- bench.MBTA              // N/A 1ms might be off by 50% <-- mbta
Parsed in 263ms on average   -- bench.Trade             // 150MB all columns, 570 MB/s
Parsed in 117ms on average   -- bench.StateDepartment   //  70MB all columns, 598 MB/s
Number of US-MA population: 5988064 in 420 ms           // 144MB all columns, 342 MB/s
Total population: 2289584999 in 291 ms                  // 144MB few columns, 494 MB/s
```

I think the closest comparissons are:

- `count_nfl_deserialize_owned_bytes` (367 MB/s) vs `bench.NFL` (325 MB/s).
- `count_pop_deserialize_owned_bytes` (206 MB/s) vs `bench.FullPopulation` (344 MB/s).

This zig library is not doing UTF validation (thus `bytes`) and it is allocating strings to be owned by the caller (thus `owned`).

## C++

I was able to get the [cpp/csv-parser](https://github.com/vincentlaucsb/csv-parser) benchmarks with optimizations making the following changes to the `Makefile`:

```diff
- CMAKE_CXX_FLAGS:STRING=
+ CMAKE_CXX_FLAGS:STRING=-std=c++17 -O3 -flto -finline-functions -funroll-loops -march=native
```

```sh
$ make csv_bench

-- Configuring done (0.1s)
-- Generating done (0.0s)
-- Build files have been written to: /Users/bensu/dev/c/csv-parser
[ 83%] Built target csv
[100%] Built target csv_bench

$ programs/csv_bench /Users/bensu/dev/c/csv-parser/tests/data/real_data/2015_StateDepartment.csv

Parsing took (including disk IO): 0.143332
Parsing took: 0.033895
```

So, in my computer, parsing that 70MB file takes 143ms when you include disk IO (489MB/s) which is comparable to the 117ms (598 MB/s) this zig library takes.

## Java

Running [java/csv-benchmark](https://github.com/skjolber/csv-benchmark):

```sh
$ mvn clean package
$ java -jar target/csv-parsers-comparison-1.0-uber.jar src/main/resources

Loop 1 - executing Bean IO Parser... took 2741 ms to read 3173959 rows.
Loop 1 - executing Apache Commons CSV... took 1837 ms to read 3173959 rows.
Loop 1 - executing Esperio CSV parser... took 31212 ms to read 3173959 rows.
Loop 1 - executing Gen-Java CSV... took 2482 ms to read 3173959 rows.
Loop 1 - executing Java CSV Parser... took 1079 ms to read 3173959 rows.
Loop 1 - executing JCSV Parser... took 943 ms to read 3173959 rows.
Loop 1 - executing OpenCSV... took 1095 ms to read 3173959 rows.
Loop 1 - executing Simple CSV parser... took 1313 ms to read 3173959 rows.
Loop 1 - executing SuperCSV... took 1263 ms to read 3173958 rows.
Loop 1 - executing Way IO Parser... took 1709 ms to read 3173959 rows.
Loop 1 - executing Oster Miller CSV parser... took 1420 ms to read 3173959 rows.
Loop 1 - executing Jackson CSV parser... took 883 ms to read 3173959 rows.
Loop 1 - executing SimpleFlatMapper CSV parser... took 800 ms to read 3173959 rows.
Loop 1 - executing Product Collections parser... took 1150 ms to read 3173959 rows.

...


=========
 AVERAGES
=========

| SimpleFlatMapper CSV parser 	 | 730 ms  	     | Best time | 704 ms 	 | 751 ms   |
| Jackson CSV parser 	         | 884 ms      	 | 21%  	 | 843 ms 	 | 931 ms   |
| JCSV Parser 	                 | 960 ms  	     | 31%  	 | 927 ms 	 | 1038 ms  |
| Java CSV Parser 	             | 1007 ms  	 | 37%  	 | 975 ms 	 | 1034 ms  |
| Product Collections parser 	 | 1068 ms  	 | 46%  	 | 1036 ms 	 | 1122 ms  |
| Simple CSV parser          	 | 1129 ms  	 | 54%  	 | 1099 ms 	 | 1158 ms  |
| SuperCSV 	                     | 1192 ms  	 | 63%  	 | 1151 ms 	 | 1275 ms  |
| OpenCSV 	                     | 1216 ms  	 | 66%  	 | 1148 ms 	 | 1255 ms  |
| Oster Miller CSV parser 	     | 1425 ms  	 | 95%  	 | 1372 ms 	 | 1506 ms  |
| Way IO Parser 	             | 1737 ms  	 | 137%  	 | 1686 ms 	 | 1775 ms  |
| Apache Commons CSV 	 		 | 1859 ms  	 | 154%  	 | 1835 ms 	 | 1884 ms  |
| Gen-Java CSV 	 				 | 2488 ms  	 | 240%  	 | 2451 ms 	 | 2573 ms  |
| Bean IO Parser 	 			 | 2734 ms  	 | 274%  	 | 2663 ms 	 | 2865 ms  |
| Esperio CSV parser 	 		 | 31535 ms  	 | 4219%  	 | 31107 ms  | 32137 ms |
```

You can see the best time is 730ms for a 144MB file which is around 197 MB/s. This library takes 435ms and 331 MB/s for the same file.

To make this compile in the `java` versions I have installed in my machine (latest?) I had to remove two parser libraries (`UnivocityParser`, `ProductCollectionsParser`) from the benchmark that used the word `Record` which conflicts with a new Java reserved keyword.
