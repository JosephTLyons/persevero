import bigben/clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{fake_wait}
import persevero.{
  MaxAttempts, OperationDuration, RetryData, WaitDuration, all_errors,
}

// -------------------- Success

pub fn positive_4_linear_backoff_is_successful_test() {
  let RetryData(result, durations, _) =
    persevero.linear_backoff(100, 100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: fn(attempt, _) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          3 -> #(4, Ok(ValidData))
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Ok(ValidData)
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(100),
      OperationDuration(2),
      WaitDuration(200),
      OperationDuration(3),
      WaitDuration(300),
      OperationDuration(4),
    ]
}

pub fn positive_4_negative_wait_duration_linear_backoff_is_successful_test() {
  let RetryData(result, durations, _) =
    persevero.linear_backoff(-100, -1000)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: fn(attempt, _) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Ok(SuccessfulConnection))
          3 -> #(4, Error(InvalidResponse))
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Ok(SuccessfulConnection)
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
