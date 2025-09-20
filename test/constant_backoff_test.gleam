import bigben/clock
import bigben/fake_clock
import gleam/list
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{advance_fake_clock_ms, build_fake_operation}
import persevero.{
  Expiry, MaxAttempts, OperationDuration, RetriesExhausted, RetryData,
  TimeExhausted, UnallowedError, WaitDuration, all_errors,
}

// -------------------- Success

pub fn positive_4_constant_backoff_with_some_allowed_errors_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | ServerUnavailable -> True
          _ -> False
        }
      },
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
      WaitDuration(100),
      OperationDuration(2),
      WaitDuration(100),
      OperationDuration(3),
    ]
  assert total_duration == 206
}

pub fn positive_4_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
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
      WaitDuration(100),
      OperationDuration(3),
      WaitDuration(100),
      OperationDuration(4),
    ]
  assert total_duration == 310
}

pub fn expiry_300_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(300),
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
      WaitDuration(100),
      OperationDuration(3),
      WaitDuration(100),
      OperationDuration(4),
    ]
  assert total_duration == 310
}

// -------------------- Failure

pub fn negative_1_times_fails_with_retries_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(-1),
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
  assert result == Error(RetriesExhausted([]))
  assert durations == []
  assert total_duration == 0
}

pub fn positive_0_times_fails_with_retries_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(0),
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
  assert result == Error(RetriesExhausted([]))
  assert durations == []
  assert total_duration == 0
}

pub fn positive_1_times_fails_with_retries_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(1),
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
  assert result == Error(RetriesExhausted([ConnectionTimeout]))
  assert durations == [WaitDuration(0), OperationDuration(1)]
  assert total_duration == 1
}

pub fn positive_3_times_fails_with_retries_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
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
      RetriesExhausted([ConnectionTimeout, ServerUnavailable, InvalidResponse]),
    )
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(100),
      OperationDuration(2),
      WaitDuration(100),
      OperationDuration(3),
    ]
  assert total_duration == 206
}

pub fn positive_3_times_retry_fails_on_non_allowed_error_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | InvalidResponse -> True
          _ -> False
        }
      },
      mode: MaxAttempts(3),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          3 -> #(4, Ok(SuccessfulConnection))
          _ -> panic
        }
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )
  assert result == Error(UnallowedError(ServerUnavailable))
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(100),
      OperationDuration(2),
    ]
  assert total_duration == 103
}

// Same as comment below
pub fn expiry_negative_1_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(-1),
      operation: build_fake_operation(fake_clock, fn(_) {
        #(5, Error(InvalidResponse))
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  assert result == Error(TimeExhausted([]))
  assert durations == []
  assert total_duration == 0
}

// I may want to revisit this. I'm not sure if expiry 0, or less than 0, should
// mean that one attempt is allowed. When set to MaxAttempts(0), we don't allow
// any attempts, but the first run is a 0 wait delay run, so maybe Expiry == 0
// should allow one attempt.
pub fn expiry_0_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(0),
      operation: build_fake_operation(fake_clock, fn(_) {
        #(5, Error(InvalidResponse))
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  assert result == Error(TimeExhausted([]))
  assert durations == []
  assert total_duration == 0
}

pub fn expiry_10000_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(10_000),
      operation: build_fake_operation(fake_clock, fn(_) {
        #(5, Error(InvalidResponse))
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  let expected_durations =
    [
      WaitDuration(100),
      OperationDuration(5),
    ]
    |> list.repeat(96)
    |> list.flatten
  let expected_durations = [
    WaitDuration(0),
    OperationDuration(5),
    ..expected_durations
  ]

  let expected_errors = InvalidResponse |> list.repeat(97)

  assert result == Error(TimeExhausted(expected_errors))
  assert durations == expected_durations
  assert total_duration == 10_085
}

pub fn expiry_300_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(250),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(5, Error(ConnectionTimeout))
          // 2, wait 100 (100)
          1 -> #(5, Error(ServerUnavailable))
          // 3, wait 100 (200)
          2 -> #(5, Error(InvalidResponse))
          // 4, wait 100 (300)
          3 -> #(5, Error(ServerUnavailable))
          // error - time exhausted
          4 -> #(5, Ok(ValidData))
          _ -> panic
        }
      }),
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

  assert result
    == Error(
      TimeExhausted([
        ConnectionTimeout,
        ServerUnavailable,
        InvalidResponse,
        ServerUnavailable,
      ]),
    )
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(5),
      WaitDuration(100),
      OperationDuration(5),
      WaitDuration(100),
      OperationDuration(5),
      WaitDuration(100),
      OperationDuration(5),
    ]
  assert total_duration == 320
}
