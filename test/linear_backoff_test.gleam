import bigben/clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{fake_wait}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Success

pub fn positive_4_linear_backoff_is_successful_test() {
  let RetryData(result, wait_times, _) =
    persevero.linear_backoff(100, 100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 100
          1 -> Error(ServerUnavailable)
          // 3, wait 200
          2 -> Error(InvalidResponse)
          // 4, wait 300
          // succeed
          3 -> Ok(ValidData)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Ok(ValidData)
  assert wait_times == [0, 100, 200, 300]
}

pub fn positive_4_negative_wait_time_linear_backoff_is_successful_test() {
  let RetryData(result, wait_times, _) =
    persevero.linear_backoff(-100, -1000)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 0
          1 -> Error(ServerUnavailable)
          // 3, wait 0
          // succeed
          2 -> Ok(SuccessfulConnection)
          // Doesn't reach
          3 -> Error(InvalidResponse)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Ok(SuccessfulConnection)
  assert wait_times == [0, 0, 0]
}
