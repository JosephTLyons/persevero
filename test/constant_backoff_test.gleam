import bigben/clock
import bigben/fake_clock
import gleam/list
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{advance_fake_clock_ms, fake_wait}
import persevero.{
  Exact, Expiry, MaxAttempts, OperationDuration, RetriesExhausted, RetryData,
  Spillover, TimeExhausted, UnallowedError, WaitDuration, all_errors,
}

// -------------------- Success

pub fn positive_4_constant_backoff_with_some_allowed_errors_is_successful_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | ServerUnavailable -> True
          _ -> False
        }
      },
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
      WaitDuration(100),
      OperationDuration(2),
      WaitDuration(100),
      OperationDuration(3),
    ]
}

pub fn positive_4_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
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
      WaitDuration(100),
      OperationDuration(3),
      WaitDuration(100),
      OperationDuration(4),
    ]
}

pub fn expiry_spillover_300_constant_backoff_with_all_allowed_errors_is_successful_test() {
  let expiry = 300
  let fake_clock = fake_clock.new()
  let constant_backoff_time = 100

  let RetryData(result, durations, total_duration) =
    persevero.constant_backoff(constant_backoff_time)
    |> persevero.execute_with_options(
      allow: persevero.all_errors,
      mode: Expiry(expiry, Spillover),
      // TODO: Can this be refactored into a function builder
      operation: fn(attempt, _) {
        let operation_time = attempt + 1
        advance_fake_clock_ms(fake_clock, operation_time)
        case attempt {
          0 -> #(operation_time, Error(ConnectionTimeout))
          1 -> #(operation_time, Error(ServerUnavailable))
          2 -> #(operation_time, Error(InvalidResponse))
          3 -> #(operation_time, Ok(ValidData))
          _ -> panic
        }
      },
      wait_function: advance_fake_clock_ms(fake_clock, _),
      clock: clock.from_fake(fake_clock),
    )

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
  assert total_duration == expiry
  assert result == Ok(ValidData)
}

// -------------------- Failure

pub fn negative_1_times_fails_with_retries_exhausted_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(-1),
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
  assert result == Error(RetriesExhausted([]))
  assert durations == []
}

pub fn positive_0_times_fails_with_retries_exhausted_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(0),
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
  assert result == Error(RetriesExhausted([]))
  assert durations == []
}

pub fn positive_1_times_fails_with_retries_exhausted_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: all_errors,
      mode: MaxAttempts(1),
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
  assert result == Error(RetriesExhausted([ConnectionTimeout]))
  assert durations == [WaitDuration(0), OperationDuration(1)]
}

pub fn positive_3_times_fails_with_retries_exhausted_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
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
}

pub fn positive_3_times_retry_fails_on_non_allowed_error_test() {
  let RetryData(result, durations, _) =
    persevero.constant_backoff(100)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | InvalidResponse -> True
          _ -> False
        }
      },
      mode: MaxAttempts(3),
      operation: fn(attempt, _) {
        case attempt {
          0 -> #(1, Error(ConnectionTimeout))
          1 -> #(2, Error(ServerUnavailable))
          2 -> #(3, Error(InvalidResponse))
          3 -> #(4, Ok(SuccessfulConnection))
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  assert result == Error(UnallowedError(ServerUnavailable))
  assert durations
    == [
      WaitDuration(0),
      OperationDuration(1),
      WaitDuration(100),
      OperationDuration(2),
    ]
}
// Same as comment below
// pub fn expiry_spillover_negative_1_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
//   let expiry = -1
//   let fake_clock = fake_clock.new()
//   let constant_backoff_time = 100

//   let RetryData(result, durations, duration, operation_durations) =
//     persevero.constant_backoff(constant_backoff_time)
//     |> persevero.execute_with_options(
//       allow: persevero.all_errors,
//       mode: Expiry(expiry, Spillover),
//       operation: fn(_) { #(5, Error(InvalidResponse)) },
//       wait_function: advance_fake_clock_ms(fake_clock, _),
//       clock: clock.from_fake(fake_clock),
//     )

//   assert durations == []
//   assert duration == 0
//   assert result == Error(TimeExhausted([]))
// }

// // I may want to revisit this. I'm not sure if expiry 0, or less than 0, should
// // mean that one attempt is allowed. When set to MaxAttempts(0), we don't allow
// // any attempts, but the first run is a 0 wait delay run, so maybe Expiry == 0
// // should allow one attempt.
// pub fn expiry_spillover_0_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
//   let expiry = 0
//   let fake_clock = fake_clock.new()
//   let constant_backoff_time = 100

//   let RetryData(result, durations, duration, operation_durations) =
//     persevero.constant_backoff(constant_backoff_time)
//     |> persevero.execute_with_options(
//       allow: persevero.all_errors,
//       mode: Expiry(expiry, Spillover),
//       operation: fn(_) { #(5, Error(InvalidResponse)) },
//       wait_function: advance_fake_clock_ms(fake_clock, _),
//       clock: clock.from_fake(fake_clock),
//     )

//   assert durations == []
//   assert duration == expiry
//   assert result == Error(TimeExhausted([]))
// }

// // pub fn expiry_spillover_10000_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
// //   let expiry = 10_000
// //   let fake_clock = fake_clock.new()
// //   let constant_backoff_time = 100
// //   let error = InvalidResponse

// //   let RetryData(result, durations, duration, operation_durations) =
// //     persevero.constant_backoff(constant_backoff_time)
// //     |> persevero.execute_with_options(
// //       allow: persevero.all_errors,
// //       mode: Expiry(expiry, Spillover),
// //       operation: fn(_) { #(5, Error(InvalidResponse)) },
// //       wait_function: advance_fake_clock_ms(fake_clock, _),
// //       clock: clock.from_fake(fake_clock),
// //     )

// //   let attempts = expiry / constant_backoff_time
// //   let expected_wait_durations = constant_backoff_time |> list.repeat(attempts)
// //   let expected_wait_durations = [0, ..expected_wait_durations]
// //   let expected_errors = error |> list.repeat(attempts + 1)

// //   assert durations == expected_wait_durations
// //   assert duration == expiry
// //   assert result == Error(TimeExhausted(expected_errors))
// // }

// // pub fn expiry_spillover_300_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
// //   let expiry = 250
// //   let fake_clock = fake_clock.new()
// //   let constant_backoff_time = 100

// //   let RetryData(result, durations, duration, operation_durations) =
// //     persevero.constant_backoff(constant_backoff_time)
// //     |> persevero.execute_with_options(
// //       allow: persevero.all_errors,
// //       mode: Expiry(expiry, Spillover),
// //       operation: fn(attempt) {
// //         case attempt {
// //           0 -> #(5, Error(ConnectionTimeout))
// //           // 2, wait 100 (100)
// //           1 -> #(5, Error(ServerUnavailable))
// //           // 3, wait 100 (200)
// //           2 -> #(5, Error(InvalidResponse))
// //           // 4, wait 100 (300)
// //           3 -> #(5, Error(ServerUnavailable))
// //           // error - time exhausted
// //           4 -> #(5, Ok(ValidData))
// //           _ -> panic
// //         }
// //       },
// //       wait_function: advance_fake_clock_ms(fake_clock, _),
// //       clock: clock.from_fake(fake_clock),
// //     )

// //   assert durations == [0, 100, 100, 100]
// //   assert duration == 300
// //   assert result
// //     == Error(
// //       TimeExhausted([
// //         ConnectionTimeout,
// //         ServerUnavailable,
// //         InvalidResponse,
// //         ServerUnavailable,
// //       ]),
// //     )
// // }

// // pub fn expiry_exact_250_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
// //   let expiry = 250
// //   let fake_clock = fake_clock.new()
// //   let constant_backoff_time = 100

// //   let RetryData(result, durations, duration, operation_durations) =
// //     persevero.constant_backoff(constant_backoff_time)
// //     |> persevero.execute_with_options(
// //       allow: persevero.all_errors,
// //       mode: Expiry(expiry, Exact),
// //       operation: fn(attempt) {
// //         case attempt {
// //           0 -> #(5, Error(ConnectionTimeout))
// //           // 2, wait 100 (100)
// //           1 -> #(5, Error(ServerUnavailable))
// //           // 3, wait 100 (200)
// //           2 -> #(5, Error(InvalidResponse))
// //           // 4, wait 100 (300)
// //           3 -> #(5, Error(ServerUnavailable))
// //           // error - time exhausted
// //           4 -> #(5, Ok(ValidData))
// //           _ -> panic
// //         }
// //       },
// //       wait_function: advance_fake_clock_ms(fake_clock, _),
// //       clock: clock.from_fake(fake_clock),
// //     )

// //   assert durations == [0, 100, 100, 50]
// //   assert duration == expiry
// //   assert result
// //     == Error(
// //       TimeExhausted([
// //         ConnectionTimeout,
// //         ServerUnavailable,
// //         InvalidResponse,
// //         ServerUnavailable,
// //       ]),
// //     )
// // }

// pub fn expiry_exact_negative_constant_backoff_with_all_allowed_errors_time_exhausted_test() {
//   let expiry = -1
//   let fake_clock = fake_clock.new()
//   let constant_backoff_time = 100

//   let RetryData(result, durations, duration, operation_durations) =
//     persevero.constant_backoff(constant_backoff_time)
//     |> persevero.execute_with_options(
//       allow: persevero.all_errors,
//       mode: Expiry(expiry, Exact),
//       operation: fn(attempt) {
//         case attempt {
//           0 -> #(5, Error(ConnectionTimeout))
//           // 2, wait 100 (100)
//           1 -> #(5, Error(ServerUnavailable))
//           // 3, wait 100 (200)
//           2 -> #(5, Error(InvalidResponse))
//           // 4, wait 100 (300)
//           3 -> #(5, Error(ServerUnavailable))
//           // error - time exhausted
//           4 -> #(5, Ok(ValidData))
//           _ -> panic
//         }
//       },
//       wait_function: advance_fake_clock_ms(fake_clock, _),
//       clock: clock.from_fake(fake_clock),
//     )

//   assert durations == []
//   assert duration == 0
//   assert result == Error(TimeExhausted([]))
// }
