# persevero

[![Package Version](https://img.shields.io/hexpm/v/persevero)](https://hex.pm/packages/persevero)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/persevero/)

Execute fallible operations multiple times.

## Installation

```sh
gleam add persevero
```

## Usage

A simple example:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/io
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response = {
    use <- persevero.execute(
      wait_stream: persevero.exponential_backoff(50, 2),
      allow: persevero.all_errors,
      mode: persevero.MaxAttempts(3),
    )

    httpc.send(request)
  }

  case response {
    Ok(response) if response.status == 200 ->
      io.println("Give me #prawducks. 😃")
    _ -> io.println("Guess I'll dev on Linux. 😔")
  }
}
```

A ridiculous example:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/io
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response =
    persevero.custom_backoff(wait_duration: 1000, next_wait_duration: fn(previous) {
      { previous + 100 } * 2
    })
    |> persevero.apply_multiplier(3)
    |> persevero.apply_jitter(20)
    |> persevero.apply_cap(10_000)
    |> persevero.apply_constant(7)
    |> persevero.execute(
      allow: fn(error) {
        case error {
          httpc.InvalidUtf8Response -> True
          _ -> False
        }
      },
      mode: persevero.MaxAttempts(10),
      operation: fn() { httpc.send(request) },
    )

  case response {
    Ok(response) if response.status == 200 ->
      io.println("Give me #prawducks. 😃")
    _ -> io.println("Guess I'll dev on Linux. 😔")
  }
}
```

Instead of defining a maximum number of attempts, you can use an expiry mode.
This will cause the operation to cease retrying after a specified duration.

```gleam
use <- persevero.execute(
  wait_stream: persevero.constant_backoff(100),
  allow: persevero.all_errors,
  mode: persevero.Expiry(10_000),
)
```

Use raw [`yielder`](https://hexdocs.pm/gleam_yielder/gleam/yielder.html)s for
ultimate wait stream manipulation:

```gleam
use <- persevero.execute(
  wait_stream: yielder.repeat(5)
    |> yielder.intersperse(10)
    |> yielder.cycle,
  allow: persevero.all_errors,
  mode: persevero.MaxAttempts(100),
)
```

Note that `persevero` generates a final wait stream with an initial 0 value, in
the `execute` function, after all transformations to the stream have been
applied, so the first attempt will never sleep. You do not need to account for
this in your custom wait stream.

## Targets

`persevero` supports the Erlang target.

## Inspiration

The feature set, and some of the design, is inspired by the
[`retry`](https://hex.pm/packages/retry) library for Elixir.
