import bigben/clock
import bigben/fake_clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{advance_fake_clock_ms, build_fake_operation}
import persevero.{
  MaxAttempts, OperationDuration, RetryData, WaitDuration, all_errors,
}

// -------------------- Success

pub fn positive_4_linear_backoff_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.linear_backoff(100, 100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          3 -> #(4, Ok(ValidData))
          _ -> panic
        }
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
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
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.linear_backoff(-100, -1000)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(4),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Ok(SuccessfulConnection))
          3 -> #(4, Error(InvalidResponse))
          _ -> panic
        }
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
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
