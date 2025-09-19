//// `persevero` executes a fallible operation multiple times.
////
//// ```gleam
//// import gleam/http/request
//// import gleam/httpc
//// import gleam/io
//// import persevero
////
//// pub fn main() {
////   let assert Ok(request) = request.to("https://www.apple.com")
////
////   let response = {
////     use <- persevero.execute(
////       wait_stream: persevero.exponential_backoff(50, 2),
////       allow: persevero.all_errors,
////       mode: persevero.MaxAttempts(3),
////     )
////
////     httpc.send(request)
////   }
////
////   case response {
////     Ok(response) if response.status == 200 ->
////       io.println("Give me #prawducks. 😃")
////     _ -> io.println("Guess I'll dev on Linux. 😔")
////   }
//// }
//// ```

import bigben/clock
import gleam/erlang/process
import gleam/function
import gleam/int
import gleam/list
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import gleam/yielder.{type Yielder}

/// Represents errors that can occur during execution attempts.
pub type Error(a) {
  /// Indicates that all execution attempts have been exhausted. Contains an
  /// ordered list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that the maximum duration for execution has been reached.
  /// Contains an ordered list of all errors encountered during the execution
  TimeExhausted(errors: List(a))

  /// Indicates that an error that wasn't allowed was encountered. Contains the
  /// specific error that caused execution to stop.
  UnallowedError(error: a)
}

type RetryResult(a, b) =
  Result(a, Error(b))

@internal
pub type RetryData(a, b) {
  RetryData(result: RetryResult(a, b), wait_times: List(Int), duration: Int)
}

/// Convenience function that can supplied to `execute`'s `allow` parameter to
/// allow all errors.
pub fn all_errors(_: a) -> Bool {
  True
}

/// Produces a custom ms wait stream.
pub fn custom_backoff(
  wait_time wait_time: Int,
  next_wait_time next_wait_time: fn(Int) -> Int,
) -> Yielder(Int) {
  yielder.iterate(wait_time, next_wait_time)
}

/// Produces a 0ms wait stream.
/// Ex: 0ms, 0ms, 0ms, ...
pub fn no_backoff() -> Yielder(Int) {
  yielder.repeat(0)
}

/// Produces a ms wait stream with a constant wait time.
/// Ex: 500ms, 500ms, 500ms, ...
pub fn constant_backoff(wait_time wait_time: Int) -> Yielder(Int) {
  yielder.iterate(wait_time, function.identity)
}

/// Produces a ms wait stream that increases linearly for each attempt.
/// Ex: 500ms, 1000ms, 1500ms, ...
pub fn linear_backoff(wait_time wait_time: Int, step step: Int) -> Yielder(Int) {
  yielder.iterate(wait_time, int.add(_, step))
}

/// Produces a ms wait stream that increases exponentially for each attempt.
/// time:
/// Ex: 500ms, 1000ms, 2000ms, ...
pub fn exponential_backoff(
  wait_time wait_time: Int,
  factor factor: Int,
) -> Yielder(Int) {
  yielder.iterate(wait_time, int.multiply(_, factor))
}

/// Adds a random integer between [1, `upper_bound`] to each wait time.
pub fn apply_jitter(
  wait_stream wait_stream: Yielder(Int),
  upper_bound upper_bound: Int,
) -> Yielder(Int) {
  apply_constant(wait_stream:, adjustment: int.random(upper_bound) + 1)
}

/// Adds a constant integer to each wait time.
pub fn apply_constant(
  wait_stream wait_stream: Yielder(Int),
  adjustment adjustment: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.add(_, adjustment))
}

/// Multiplies each wait time by a constant factor.
pub fn apply_multiplier(
  wait_stream wait_stream: Yielder(Int),
  factor factor: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.multiply(_, factor))
}

/// Caps each wait time at a maximum value.
pub fn apply_cap(
  wait_stream wait_stream: Yielder(Int),
  max_wait_time max_wait_time: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.min(_, max_wait_time))
}

/// Configures the retry mode.
pub type Mode {
  /// Specifies the maximum number of attempts to make.
  MaxAttempts(Int)

  /// Specifies the maximum duration, in ms, to make attempts for.
  ///
  /// The duration measured includes the time it takes to run your operation.
  /// The behavior when approaching the expiry time is controlled by the
  /// `ExpiryMode` parameter.
  Expiry(Int, mode: ExpiryMode)
}

/// Controls how the retry mechanism behaves when approaching the expiry time.
pub type ExpiryMode {
  /// Ensures the total retry duration never exceeds the expiry time by
  /// trimming the final wait time if necessary. For example, if 5ms remain
  /// until expiry and the next wait time would be 10ms, it will be trimmed
  /// to 5ms.
  Exact

  /// Allows the final wait time to complete even if it exceeds the expiry
  /// time. For example, if 5ms remain until expiry and the next wait time
  /// is 10ms, the full 10ms wait will occur, causing the total duration to
  /// exceed the expiry time.
  Spillover
}

/// Initiates the execution process with the specified operation.
///
/// `allow` sets the logic for determining whether an error should trigger
/// another attempt. Expects a function that takes an error and returns a
/// boolean. Use this function to match on the encountered error and return
/// `True` for errors that should trigger another attempt, and `False` for
/// errors that should not. To allow all errors, use `all_errors`.
pub fn execute(
  wait_stream wait_stream: Yielder(Int),
  allow allow: fn(b) -> Bool,
  mode mode: Mode,
  operation operation: fn() -> Result(a, b),
) -> RetryResult(a, b) {
  execute_with_options(
    wait_stream:,
    allow:,
    mode:,
    operation: fn(_) { operation() },
    wait_function: fn(wait_time) {
      case wait_time <= 0 {
        True -> Nil
        False -> process.sleep(wait_time)
      }
    },
    clock: clock.new(),
  ).result
}

@internal
pub fn execute_with_options(
  wait_stream wait_stream: Yielder(Int),
  allow allow: fn(b) -> Bool,
  mode mode: Mode,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  clock clock: clock.Clock,
) -> RetryData(a, b) {
  do_execute(
    wait_stream: prepare_wait_stream(wait_stream, mode, clock),
    allow:,
    mode:,
    operation:,
    wait_function:,
    wait_time_acc: [],
    errors_acc: [],
    last_duration: 0,
  )
}

@internal
pub fn prepare_wait_stream(
  wait_stream wait_stream: Yielder(Int),
  mode mode: Mode,
  clock clock: clock.Clock,
) -> Yielder(#(Int, Int, Int)) {
  let start_time = clock.now(clock)

  let wait_stream =
    wait_stream
    |> yielder.prepend(0)
    |> yielder.map(int.max(_, 0))
    |> yielder.index
    |> yielder.map(fn(wait_time_attempt) {
      let #(wait_time, attempt) = wait_time_attempt
      let duration = duration_ms(start_time, clock.now(clock))
      #(wait_time, attempt, duration)
    })

  case mode {
    MaxAttempts(max_attempts) -> yielder.take(wait_stream, max_attempts)
    Expiry(expiry, expiry_mode) -> {
      use _, tuple <- yielder.transform(wait_stream, Nil)
      let #(wait_time, attempt, duration) = tuple

      case duration >= expiry {
        True -> yielder.Done
        False -> {
          let actual_wait = case expiry_mode {
            Spillover -> wait_time
            Exact -> int.min(wait_time, expiry - duration)
          }
          let new_duration = duration_ms(start_time, clock.now(clock))
          yielder.Next(#(actual_wait, attempt, new_duration), Nil)
        }
      }
    }
  }
}

@internal
pub fn duration_ms(left: Timestamp, right: Timestamp) -> Int {
  let #(seconds, nanoseconds) =
    left
    |> timestamp.difference(right)
    |> duration.to_seconds_and_nanoseconds

  seconds * 1000 + nanoseconds / 1_000_000
}

fn do_execute(
  wait_stream wait_stream: Yielder(#(Int, Int, Int)),
  allow allow: fn(b) -> Bool,
  mode mode: Mode,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  wait_time_acc wait_time_acc: List(Int),
  errors_acc errors_acc: List(b),
  last_duration last_duration: Int,
) -> RetryData(a, b) {
  case yielder.step(wait_stream) {
    yielder.Done -> {
      let errors = list.reverse(errors_acc)
      let error = case mode {
        MaxAttempts(_) -> RetriesExhausted(errors)
        Expiry(_, _) -> TimeExhausted(errors)
      }
      RetryData(
        result: Error(error),
        wait_times: list.reverse(wait_time_acc),
        duration: last_duration,
      )
    }
    yielder.Next(#(wait_time, attempt, duration), wait_stream) -> {
      wait_function(wait_time)
      let wait_time_acc = [wait_time, ..wait_time_acc]

      case operation(attempt) {
        Ok(result) ->
          RetryData(
            result: Ok(result),
            wait_times: list.reverse(wait_time_acc),
            duration:,
          )
        Error(error) -> {
          case allow(error) {
            True ->
              do_execute(
                wait_stream:,
                allow:,
                mode:,
                operation:,
                wait_function:,
                wait_time_acc:,
                errors_acc: [error, ..errors_acc],
                last_duration: duration,
              )
            False ->
              RetryData(
                result: Error(UnallowedError(error)),
                wait_times: list.reverse(wait_time_acc),
                duration:,
              )
          }
        }
      }
    }
  }
}
// TODO: Move timing and attempt tracking to wait stream

// - [ ] Update `prepare_wait_stream` to return `Yielder(#(Int, Int, Int))` with `#(wait_time, duration, attempt)`
// - [ ] Add `clock: clock.Clock` parameter to `prepare_wait_stream`
// - [ ] Use wall-clock timing in `prepare_wait_stream` for Expiry mode (not accumulated waits)
// - [ ] Add attempt counting via `yielder.index` in the wait stream
// - [ ] Remove `attempt`, `clock`, `start_time` parameters from `do_execute`
// - [ ] Update `do_execute` to destructure tuple and use provided attempt/duration values
// - [ ] Update tests to handle new `prepare_wait_stream` return type

// GOAL: Move back to wall-time based expiry, but also keeping current implementation. Move timing logic into transform, then for consistency, move attempt counting into stream as well.

// order of tuple should be index, wait_time, duration
