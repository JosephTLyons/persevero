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
    wait_stream: prepare_wait_stream(wait_stream, mode),
    allow:,
    mode:,
    operation:,
    wait_function:,
    wait_time_acc: [],
    clock:,
    errors_acc: [],
    start_time: clock.now(clock),
    duration: 0,
  )
}

@internal
pub fn prepare_wait_stream(
  wait_stream wait_stream: Yielder(Int),
  mode mode: Mode,
) -> Yielder(#(Int, Int)) {
  let wait_stream =
    wait_stream
    |> yielder.prepend(0)
    |> yielder.map(int.max(_, 0))
    |> yielder.index

  case mode {
    MaxAttempts(max_attempts) -> yielder.take(wait_stream, max_attempts)
    Expiry(expiry, expiry_mode) -> {
      use remaining_time, tuple <- yielder.transform(wait_stream, expiry)
      let #(wait_time, attempt) = tuple
      case remaining_time {
        remaining if remaining <= 0 -> yielder.Done
        _ -> {
          let actual_wait = case expiry_mode {
            Spillover -> wait_time
            Exact -> int.min(wait_time, remaining_time)
          }
          yielder.Next(#(actual_wait, attempt), remaining_time - actual_wait)
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
  wait_stream wait_stream: Yielder(#(Int, Int)),
  allow allow: fn(b) -> Bool,
  mode mode: Mode,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  wait_time_acc wait_time_acc: List(Int),
  clock clock: clock.Clock,
  errors_acc errors_acc: List(b),
  start_time start_time: Timestamp,
  duration duration: Int,
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
        duration:,
      )
    }
    yielder.Next(#(wait_time, attempt), wait_stream) -> {
      wait_function(wait_time)
      let wait_time_acc = [wait_time, ..wait_time_acc]
      let duration = clock |> clock.now |> duration_ms(start_time, _)

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
                clock:,
                errors_acc: [error, ..errors_acc],
                start_time:,
                duration:,
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
