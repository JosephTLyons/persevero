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

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_constant_multiplier_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(50, 2)
    |> persevero.apply_constant(1)
    |> persevero.apply_multiplier(3)
    |> persevero.apply_constant(1)
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
          // 2, wait 100
          1 -> #(2, Error(ServerUnavailable))
          // 3, wait 100
          // succeed
          2 -> #(3, Ok(SuccessfulConnection))
          // Doesn't reach
          3 -> #(4, Error(InvalidResponse))
          _ -> panic
        }
      }),
      wait_function: utils.advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )
  assert result == Ok(SuccessfulConnection)
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(154),
      OperationDuration(2),
      WaitDuration(304),
      OperationDuration(3),
    ]
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_cap_constant_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(50, 3)
    |> persevero.apply_cap(100)
    |> persevero.apply_constant(3)
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
      WaitDuration(53),
      OperationDuration(2),
      WaitDuration(103),
      OperationDuration(3),
    ]
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_constant_cap_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(50, 2)
    |> persevero.apply_constant(3)
    |> persevero.apply_cap(100)
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
      WaitDuration(53),
      OperationDuration(2),
      WaitDuration(100),
      OperationDuration(3),
    ]
}

pub fn positive_4_exponential_backoff_on_all_allowed_errors_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(100, 2)
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
      WaitDuration(400),
      OperationDuration(4),
    ]
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(100, 3)
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
      WaitDuration(300),
      OperationDuration(3),
    ]
}

pub fn positive_5_exponential_backoff_on_some_allowed_errors_with_apply_cap_is_successful_test() {
  let fake_clock = fake_clock.new()

  let RetryData(result, durations, _) =
    persevero.exponential_backoff(500, 2)
    |> persevero.apply_cap(1000)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | ServerUnavailable -> True
          _ -> False
        }
      },
      mode: MaxAttempts(5),
      operation: build_fake_operation(fake_clock, fn(attempt) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(ConnectionTimeout))
          3 -> #(4, Error(ServerUnavailable))
          4 -> #(5, Ok(SuccessfulConnection))
          5 -> #(6, Error(InvalidResponse))
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
      WaitDuration(500),
      OperationDuration(2),
      WaitDuration(1000),
      OperationDuration(3),
      WaitDuration(1000),
      OperationDuration(4),
      WaitDuration(1000),
      OperationDuration(5),
    ]
}
// TODO: Remove all fake operation comments
