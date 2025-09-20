import bigben/clock
import bigben/fake_clock
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable,
}
import internal/utils.{advance_fake_clock_ms, build_fake_operation}
import persevero.{
  MaxAttempts, OperationDuration, RetryData, WaitDuration, all_errors,
}

// -------------------- Failure

// TODO: can operation be the only place that calls advance_fake_clock_ms and
// then we skip passing the `wait_function`

pub fn positive_3_no_backoff_fails_with_retries_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.no_backoff()
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(3),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          _ -> panic
        }
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
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
  assert total_duration == 6
}
