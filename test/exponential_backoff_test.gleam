import bigben/clock
import gleeunit/should
import internal/mock_types.{
  ConnectionTimeout, InvalidResponse, ServerUnavailable, SuccessfulConnection,
  ValidData,
}
import internal/utils.{fake_wait}
import persevero.{MaxAttempts, RetryData, all_errors}

// -------------------- Success

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_constant_multiplier_is_successful_test() {
  let RetryData(result, wait_times, _) =
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
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 100
          1 -> Error(ServerUnavailable)
          // 3, wait 100
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
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 154, 304])
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_cap_constant_is_successful_test() {
  let RetryData(result, wait_times, _) =
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
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 53
          1 -> Error(ServerUnavailable)
          // 3, wait 103
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
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 53, 103])
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_with_apply_constant_cap_is_successful_test() {
  let RetryData(result, wait_times, _) =
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
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 53
          1 -> Error(ServerUnavailable)
          // 3, wait 100
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
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 53, 100])
}

pub fn positive_4_exponential_backoff_on_all_allowed_errors_is_successful_test() {
  let RetryData(result, wait_times, _) =
    persevero.exponential_backoff(100, 2)
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
          // 4, wait 400
          // succeed
          3 -> Ok(ValidData)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(ValidData))
  wait_times |> should.equal([0, 100, 200, 400])
}

pub fn positive_4_exponential_backoff_on_some_allowed_errors_is_successful_test() {
  let RetryData(result, wait_times, _) =
    persevero.exponential_backoff(100, 3)
    |> persevero.execute_with_options(
      allow: fn(error) {
        case error {
          ConnectionTimeout | ServerUnavailable -> True
          _ -> False
        }
      },
      mode: MaxAttempts(4),
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 100
          1 -> Error(ServerUnavailable)
          // 3, wait 300
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
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 100, 300])
}

pub fn positive_5_exponential_backoff_on_some_allowed_errors_with_apply_cap_is_successful_test() {
  let RetryData(result, wait_times, _) =
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
      operation: fn(attempt) {
        case attempt {
          // 1, wait 0
          0 -> Error(ConnectionTimeout)
          // 2, wait 500
          1 -> Error(ServerUnavailable)
          // 3, wait 1000
          2 -> Error(ConnectionTimeout)
          // 4, wait 1000
          3 -> Error(ServerUnavailable)
          // 5, wait 1000
          // succeed
          4 -> Ok(SuccessfulConnection)
          // Doesn't reach
          5 -> Error(InvalidResponse)
          _ -> panic
        }
      },
      wait_function: fake_wait,
      clock: clock.new(),
    )
  result |> should.equal(Ok(SuccessfulConnection))
  wait_times |> should.equal([0, 500, 1000, 1000, 1000])
}
