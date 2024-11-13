import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import list_extensions.{at}
import retry.{retry_with_sleep}
import retry_error.{AllAttemptsExhausted, UnallowedError}

pub fn main() {
  gleeunit.main()
}

type MockNetworkError {
  ConnectionTimeout
  ServerUnavailable
  InvalidResponse
}

type MockNetworkResponse {
  SuccessfulConnection
  ValidData
}

const sleep_time_in_ms = 100

pub fn retry_with_negative_times_returns_error_test() {
  let times = -1
  let result_returning_operationtion =
    result_returning_operationtion(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    allowed_errors: [],
    operation: result_returning_operationtion,
  )
  |> should.equal(Error(AllAttemptsExhausted([])))
}

pub fn retry_fails_after_exhausting_attempts_test() {
  let times = 2
  let result_returning_operationtion =
    result_returning_operationtion(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    allowed_errors: [],
    operation: result_returning_operationtion,
  )
  |> should.equal(
    Error(
      AllAttemptsExhausted([
        InvalidResponse,
        ServerUnavailable,
        ConnectionTimeout,
      ]),
    ),
  )
}

pub fn retry_stops_on_non_allowed_error_test() {
  let times = 3
  let result_returning_operationtion =
    result_returning_operationtion(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
      Ok(SuccessfulConnection),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    allowed_errors: [ConnectionTimeout, InvalidResponse],
    operation: result_returning_operationtion,
  )
  |> should.equal(Error(UnallowedError(ServerUnavailable)))
}

pub fn retry_succeeds_on_allowed_errors_test() {
  let times = 3
  let result_returning_operationtion =
    result_returning_operationtion(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
      Ok(SuccessfulConnection),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    allowed_errors: [ConnectionTimeout, ServerUnavailable, InvalidResponse],
    operation: result_returning_operationtion,
  )
  |> should.equal(Ok(SuccessfulConnection))
}

pub fn retry_succeeds_after_allowed_errors_test() {
  let times = 3
  let result_returning_operationtion =
    result_returning_operationtion(times: times, results: [
      Error(ConnectionTimeout),
      Error(ServerUnavailable),
      Error(InvalidResponse),
      Ok(ValidData),
    ])

  retry_with_sleep(
    times: times,
    sleep_time_in_ms: sleep_time_in_ms,
    sleep: fake_sleep,
    allowed_errors: [],
    operation: result_returning_operationtion,
  )
  |> should.equal(Ok(ValidData))
}

fn fake_sleep(_) {
  Nil
}

fn result_returning_operationtion(
  times times: Int,
  results results: List(Result(a, b)),
) -> fn(Int) -> Result(a, b) {
  let panic_message =
    "Need to provide more than " <> times |> int.to_string <> " results"

  fn(count) {
    let result = results |> at(index: count)
    case result {
      Some(result) -> result
      None -> panic as panic_message
    }
  }
}