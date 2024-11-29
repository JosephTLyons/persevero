# Changelog

## v1.1.0 - 2024-11-29

- Added support for expiry mode.

This is a breaking change. For existing code, any calls to execute will need to
be adjusted.

`max_attempts: 3` -> `mode: persevero.MaxAttempts(3)`

To use expiry mode, use `persevero.Expiry` when calling `execute`.

`mode: persevero.Expiry(10_000)` - will expire after 10 seconds.

A new error type has been added: `TimeExhausted`. This will also be a breaking
change for any code that had previously matched exhaustively on error types
returned from `execute`.


## v1.0.0 - 2024-11-27

- API stabilized.

## v0.1.0 - 2024-11-26

- Initial release.
