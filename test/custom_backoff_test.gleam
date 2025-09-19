import bigben/clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, ValidData,
}
import internal/utils.{fake_wait}
import persevero.{
  MaxAttempts, OperationDuration, RetryData, WaitDuration, all_errors,
}

// -------------------- Success

pub fn positive_4_custom_backoff_is_successful_test() {
  let RetryData(result, durations, _) =
    persevero.custom_backoff(
      wait_duration: 100,
      next_wait_duration: fn(previous) { { previous + 100 } * 2 },
    )
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
      WaitDuration(400),
      OperationDuration(3),
      WaitDuration(1000),
      OperationDuration(4),
    ]
}
// TODO: Assert final duration
