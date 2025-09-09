import bigben/clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, ValidData,
}
import internal/utils.{fake_wait}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Success

pub fn positive_4_custom_backoff_is_successful_test() {
  let RetryData(result, wait_times, _) =
    persevero.custom_backoff(wait_time: 100, next_wait_time: fn(previous) {
      { previous + 100 } * 2
    })
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 100
          1 -> Error(ServerUnavailable)
          // 3, wait 400
          2 -> Error(InvalidResponse)
          // 4, wait 1000
          // succeed
          3 -> Ok(ValidData)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Ok(ValidData)
  assert wait_times == [0, 100, 400, 1000]
}
