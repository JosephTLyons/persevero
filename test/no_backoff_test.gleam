import bigben/clock
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable,
}
import internal/utils.{fake_wait}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Failure

pub fn positive_3_no_backoff_fails_with_retries_exhausted_test() {
  let RetryData(result, wait_times, _) =
    persevero.no_backoff()
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(3),
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 0
          1 -> Error(ServerUnavailable)
          // 3, wait 0
          // error
          2 -> Error(InvalidResponse)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result
  |> should.equal(
    Error(
      persevero.RetriesExhausted([
        ConnectionTimeout,
        ServerUnavailable,
        InvalidResponse,
      ]),
    ),
  )
  wait_times |> should.equal([0, 0, 0])
}
