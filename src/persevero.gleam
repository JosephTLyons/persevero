//// `persevero` executes a fallible operation multiple times.

import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/yielder.{type Yielder}

/// Represents errors that can occur during execution attempts.
pub type Error(a) {
  /// Indicates that all execution attempts have been exhausted. Contains an
  /// ordered list of all errors encountered during the execution attempts.
  RetriesExhausted(errors: List(a))

  /// Indicates that an error that wasn't allowed was encountered. Contains the
  /// specific error that caused execution to stop.
  UnallowedError(error: a)
}

type RetryResult(a, b) =
  Result(a, Error(b))

@internal
pub type RetryData(a, b) {
  RetryData(result: RetryResult(a, b), wait_times: List(Int))
}

/// Convenience function: provide this to `new`'s `backoff` parameter for no
/// backoff. Equivalent to passing `fn(_) { 0 }`. Warning: You usually do not
/// want to use this function, as it will produce a stream of 0s, regardless of
/// the initial wait time.
pub fn no_backoff(_: Int) -> Int {
  0
}

/// Convenience function: provide this to `new`'s `backoff` parameter for
/// constant backoff. Equivalent to passing `function.identity`.
pub fn constant_backoff(wait_time wait_time: Int) -> Int {
  wait_time
}

/// Convenience function: provide this to `new`'s `backoff` parameter for linear
/// backoff. Evuivalent to passing `int.add`.
pub fn linear_backoff(wait_time wait_time: Int, increment increment: Int) -> Int {
  wait_time + increment
}

/// Convenience function: provide this to `new`'s `backoff` parameter for
/// exponential backoff. Equivalent to passing `int.multiply`.
pub fn exponential_backoff(wait_time wait_time: Int, factor factor: Int) -> Int {
  wait_time * factor
}

/// Creates a new configuration with the specified `wait_time` and `backoff`
/// function.
///
/// The `backoff` function determines how the wait time changes between
/// attempts. It takes the previous wait time as input and returns the next wait
/// time.
pub fn new(
  wait_time wait_time: Int,
  backoff backoff: fn(Int) -> Int,
) -> Yielder(Int) {
  // This feels a bit of a hacky way to handle a bug in no_backoff - find a
  // better solution
  let wait_time = case backoff(wait_time) {
    0 -> 0
    _ -> wait_time
  }
  yielder.unfold(wait_time, fn(acc) { yielder.Next(acc, backoff(acc)) })
}

/// Adds a random integer between [1, `upper_bound`] to each wait time.
pub fn apply_jitter(
  yielder yielder: Yielder(Int),
  upper_bound upper_bound: Int,
) -> Yielder(Int) {
  apply_constant(yielder: yielder, adjustment: int.random(upper_bound) + 1)
}

/// Adds a constant integer to each wait time.
pub fn apply_constant(
  yielder yielder: Yielder(Int),
  adjustment adjustment: Int,
) -> Yielder(Int) {
  yielder |> yielder.map(int.add(_, adjustment))
}

/// Sets a maximum time limit to wait between execution attempts.
pub fn max_wait_time(
  yielder yielder: Yielder(Int),
  max_wait_time max_wait_time: Int,
) -> Yielder(Int) {
  yielder |> yielder.map(int.min(_, max_wait_time))
}

/// Initiates the execution process with the specified operation.
///
/// `allow` sets the logic for determining whether an error should trigger
/// another attempt. Expects a function that takes an error and returns a
/// boolean. Use this function to match on the encountered error and return
/// `True` for errors that should trigger another attempt, and `False` for
/// errors that should not. To allow all errors, use `fn(_) { True }`.
pub fn execute(
  yielder yielder: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn() -> Result(a, b),
) -> RetryResult(a, b) {
  execute_with_wait(
    yielder: yielder,
    allow: allow,
    max_attempts: max_attempts,
    operation: fn(_) { operation() },
    wait_function: process.sleep,
  ).result
}

@internal
pub fn execute_with_wait(
  yielder yielder: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
) -> RetryData(a, b) {
  case max_attempts <= 0 {
    True -> RetryData(result: Error(RetriesExhausted([])), wait_times: [])
    False -> {
      let yielder = yielder |> yielder.take(max_attempts - 1)
      let yielder =
        yielder.from_list([0])
        |> yielder.append(yielder)
        |> yielder.map(int.max(_, 0))

      do_execute(
        yielder: yielder,
        allow: allow,
        max_attempts: max_attempts,
        operation: operation,
        wait_function: wait_function,
        wait_time_acc: [],
        errors_acc: [],
        attempt_number: 0,
      )
    }
  }
}

fn do_execute(
  yielder yielder: Yielder(Int),
  allow allow: fn(b) -> Bool,
  max_attempts max_attempts: Int,
  operation operation: fn(Int) -> Result(a, b),
  wait_function wait_function: fn(Int) -> Nil,
  wait_time_acc wait_time_acc: List(Int),
  errors_acc errors_acc: List(b),
  attempt_number attempt_number: Int,
) -> RetryData(a, b) {
  case yielder |> yielder.step() {
    yielder.Next(wait_time, yielder) -> {
      wait_function(wait_time)
      let wait_time_acc = [wait_time, ..wait_time_acc]

      case operation(attempt_number) {
        Ok(result) ->
          RetryData(
            result: Ok(result),
            wait_times: wait_time_acc |> list.reverse,
          )
        Error(error) -> {
          case allow(error) {
            True ->
              do_execute(
                yielder: yielder,
                allow: allow,
                max_attempts: max_attempts,
                operation: operation,
                wait_function: wait_function,
                wait_time_acc: wait_time_acc,
                errors_acc: [error, ..errors_acc],
                attempt_number: attempt_number + 1,
              )
            False ->
              RetryData(
                result: Error(UnallowedError(error)),
                wait_times: wait_time_acc |> list.reverse,
              )
          }
        }
      }
    }
    yielder.Done ->
      RetryData(
        result: Error(RetriesExhausted(errors_acc |> list.reverse)),
        wait_times: wait_time_acc |> list.reverse,
      )
  }
}
