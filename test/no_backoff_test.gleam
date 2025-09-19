import bigben/clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable,
}
import internal/utils.{fake_wait}
import persevero.{
  MaxAttempts, OperationDuration, RetryData, WaitDuration, all_errors,
}

// -------------------- Failure

pub fn positive_3_no_backoff_fails_with_retries_exhausted_test() {
  let RetryData(result, durations, _) =
    persevero.no_backoff()
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(3),
      operation: fn(attempt, _) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result
    == Error(
      persevero.RetriesExhausted([
        ConnectionTimeout,
        ServerUnavailable,
        InvalidResponse,
      ]),
    )
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(0),
      OperationDuration(2),
      WaitDuration(0),
      OperationDuration(3),
    ]
}
