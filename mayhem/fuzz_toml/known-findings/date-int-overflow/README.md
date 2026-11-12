# tomlc17 `read_int()` signed overflow on a long date field

`repro.toml` -> `fuzz_toml-standalone repro.toml` stops with UBSan:
`src/config/tomlc17/tomlc17.c:1949:15: runtime error: signed integer overflow: 222222222 * 10 cannot be represented in type 'int'`.

Cause: `read_int()` accumulates digits into an `int` and detects overflow *afterwards* with `if (val < 0)`,
which is itself undefined behavior for signed arithmetic. Any date or time field with more than nine digits
(year, month, day, hour, ...) reaches it, e.g. from a user-supplied `pihole.toml` or Teleporter import.

Fix: check `val > (INT_MAX - digit) / 10` before multiplying (or accumulate in `unsigned`/`int64_t`).
