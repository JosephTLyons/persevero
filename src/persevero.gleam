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

// TODO: Make each internal int its own type so that we can't accidentally pass
// the wrong one around, including attempt
@internal
pub type Duration {
  WaitDuration(Int)
  OperationDuration(Int)
}

@internal
pub type RetryData(a, b) {
  RetryData(
    result: RetryResult(a, b),
    durations: List(Duration),
    total_duration: Int,
  )
}

@internal
pub type StreamData(a, b) {
  StreamData(
    wait_duration: Int,
    attempt: Int,
    operation_duration: Int,
    operation_result: Result(a, b),
    total_duration: Int,
  )
}

/// Convenience function that can supplied to `execute`'s `allow` parameter to
/// allow all errors.
pub fn all_errors(_: a) -> Bool {
  True
}

/// Produces a custom ms wait stream.
pub fn custom_backoff(
  wait_duration wait_duration: Int,
  next_wait_duration next_wait_duration: fn(Int) -> Int,
) -> Yielder(Int) {
  yielder.iterate(wait_duration, next_wait_duration)
}

/// Produces a 0ms wait stream.
/// Ex: 0ms, 0ms, 0ms, ...
pub fn no_backoff() -> Yielder(Int) {
  yielder.repeat(0)
}

/// Produces a ms wait stream with a constant wait time.
/// Ex: 500ms, 500ms, 500ms, ...
pub fn constant_backoff(wait_duration wait_duration: Int) -> Yielder(Int) {
  yielder.iterate(wait_duration, function.identity)
}

/// Produces a ms wait stream that increases linearly for each attempt.
/// Ex: 500ms, 1000ms, 1500ms, ...
pub fn linear_backoff(
  wait_duration wait_duration: Int,
  step step: Int,
) -> Yielder(Int) {
  yielder.iterate(wait_duration, int.add(_, step))
}

/// Produces a ms wait stream that increases exponentially for each attempt.
/// time:
/// Ex: 500ms, 1000ms, 2000ms, ...
pub fn exponential_backoff(
  wait_duration wait_duration: Int,
  factor factor: Int,
) -> Yielder(Int) {
  yielder.iterate(wait_duration, int.multiply(_, factor))
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
  max_wait_duration max_wait_duration: Int,
) -> Yielder(Int) {
  wait_stream |> yielder.map(int.min(_, max_wait_duration))
}

/// Configures the retry mode.
pub type Mode {
  /// Specifies the maximum number of attempts to make.
  MaxAttempts(Int)

  /// Specifies the maximum duration, in ms, to make attempts for.
  ///
  /// The duration measured includes the time it takes to run your operation.
  Expiry(Int)
}

// TODO: Have agent explain and document when expiry stops

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
    operation: fn(_, clock) {
      let start = clock.now(clock)
      let operation_result = operation()
      let end = clock.now(clock)
      #(duration_ms(start, end), operation_result)
    },
    wait_function: fn(wait_duration) {
      case wait_duration <= 0 {
        True -> Nil
        False -> process.sleep(wait_duration)
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
  operation operation: fn(Int, clock.Clock) -> #(Int, Result(a, b)),
  wait_function wait_function: fn(Int) -> Nil,
  clock clock: clock.Clock,
) -> RetryData(a, b) {
  do_execute(
    wait_stream: prepare_wait_stream(
      wait_stream,
      wait_function,
      mode,
      operation,
      clock,
    ),
    allow:,
    mode:,
    durations: [],
    errors_acc: [],
    total_duration: 0,
  )
}

@internal
pub fn prepare_wait_stream(
  wait_stream wait_stream: Yielder(Int),
  wait_function wait_function: fn(Int) -> Nil,
  mode mode: Mode,
  operation operation: fn(Int, clock.Clock) -> #(Int, Result(a, b)),
  clock clock: clock.Clock,
) -> Yielder(StreamData(a, b)) {
  let start_time = clock.now(clock)

  let wait_stream =
    wait_stream
    |> yielder.prepend(0)
    |> yielder.map(int.max(_, 0))
    |> yielder.index

  case mode {
    MaxAttempts(max_attempts) -> {
      wait_stream
      |> yielder.take(max_attempts)
      |> yielder.map(fn(wait_duration_attempt) {
        let #(wait_duration, attempt) = wait_duration_attempt
        // Clean up duplicate between two mode branches
        case attempt {
          0 -> Nil
          _ -> wait_function(wait_duration)
        }
        let #(operation_duration, operation_result) = operation(attempt, clock)
        let total_duration = duration_ms(start_time, clock.now(clock))
        StreamData(
          wait_duration,
          attempt,
          operation_duration,
          operation_result,
          total_duration,
        )
      })
    }
    Expiry(expiry) -> {
      wait_stream
      |> yielder.transform(Nil, fn(_, wait_duration_attempt) {
        let #(wait_duration, attempt) = wait_duration_attempt
        let total_duration = duration_ms(start_time, clock.now(clock))
        case total_duration < expiry {
          True -> {
            case attempt {
              0 -> Nil
              _ -> wait_function(wait_duration)
            }
            let #(operation_duration, operation_result) =
              operation(attempt, clock)
            let total_duration = duration_ms(start_time, clock.now(clock))

            yielder.Next(
              StreamData(
                wait_duration,
                attempt,
                operation_duration,
                operation_result,
                total_duration,
              ),
              Nil,
            )
          }
          False -> yielder.Done
        }
      })
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

// TODO: Move all of this into yielder
fn do_execute(
  wait_stream wait_stream: Yielder(StreamData(a, b)),
  allow allow: fn(b) -> Bool,
  mode mode: Mode,
  durations durations: List(Duration),
  errors_acc errors_acc: List(b),
  total_duration total_duration: Int,
) -> RetryData(a, b) {
  case yielder.step(wait_stream) {
    yielder.Done -> {
      let errors = list.reverse(errors_acc)
      let error = case mode {
        MaxAttempts(_) -> RetriesExhausted(errors)
        Expiry(_) -> TimeExhausted(errors)
      }
      RetryData(
        result: Error(error),
        durations: list.reverse(durations),
        total_duration:,
      )
    }
    yielder.Next(
      StreamData(
        wait_duration,
        _,
        operation_duration,
        operation_result,
        total_duration,
      ),
      wait_stream,
    ) -> {
      let durations = [
        OperationDuration(operation_duration),
        WaitDuration(wait_duration),
        ..durations
      ]
      case operation_result {
        Ok(result) ->
          RetryData(
            result: Ok(result),
            durations: list.reverse(durations),
            total_duration:,
          )
        Error(error) -> {
          case allow(error) {
            True ->
              do_execute(
                wait_stream:,
                allow:,
                mode:,
                durations: durations,
                errors_acc: [error, ..errors_acc],
                total_duration:,
              )
            False ->
              RetryData(
                result: Error(UnallowedError(error)),
                durations: list.reverse(durations),
                total_duration:,
              )
          }
        }
      }
    }
  }
}
// - [ ] Use wall-clock timing in `prepare_wait_stream` for Expiry mode (not accumulated waits)
//    verify with agent

// ordering of StreamData

// TODO: Have yielder return RetryData directly (or YielderData), then we just
// need execute to run through the generator and return
