# TRE regex compile/match takes seconds on a 30-byte pattern

`repro.bin` is `<pattern>\0<subject>`: pattern ``[a\xff\xff\xff\xff\xff\xff]{2,}\d$\0-+`` (the `\0` is a literal backslash and zero) with a subject of seven 0xff bytes and `f`.
`fuzz_regex-standalone repro.bin` needs about 2.5 s under ASan+UBSan on a developer machine (libFuzzer's
`-timeout=3` flags it as a slow unit when the host is slower).

Cause: a bounded repetition (`{2,}`) of a bracket expression compiles to a large automaton in
`src/tre-regex/tre-compile.c`/`tre-match-*.c`; regexes are user-supplied through the Pi-hole regex filter
lists, so a pathological filter can stall the DNS resolver thread that matches it.

Fix idea: cap repetition bounds / automaton size when compiling user regexes in `src/regex.c`.
