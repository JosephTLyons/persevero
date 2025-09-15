import gleam/int
import gleam/yielder
import persevero

// Test stream generators ------------------------------------------------------

pub fn custom_backoff_test() {
  assert persevero.custom_backoff(2, int.add(2, _))
    |> yielder.take(5)
    |> yielder.to_list
    == [2, 4, 6, 8, 10]
}

pub fn no_backoff_test() {
  assert persevero.no_backoff() |> yielder.take(5) |> yielder.to_list
    == [0, 0, 0, 0, 0]
}

pub fn constant_backoff_test() {
  assert persevero.constant_backoff(2) |> yielder.take(5) |> yielder.to_list
    == [2, 2, 2, 2, 2]
}

pub fn linear_backoff_test() {
  assert persevero.linear_backoff(5, 5) |> yielder.take(5) |> yielder.to_list
    == [5, 10, 15, 20, 25]
}

pub fn exponential_backoff_test() {
  assert persevero.exponential_backoff(2, 2)
    |> yielder.take(5)
    |> yielder.to_list
    == [2, 4, 8, 16, 32]
}

// Test stream transformers ----------------------------------------------------

pub fn apply_constant_test() {
  assert persevero.linear_backoff(5, 5)
    |> persevero.apply_constant(1)
    |> yielder.take(5)
    |> yielder.to_list
    == [6, 11, 16, 21, 26]
}

pub fn apply_multiplier_test() {
  assert persevero.linear_backoff(5, 5)
    |> persevero.apply_multiplier(2)
    |> yielder.take(5)
    |> yielder.to_list
    == [10, 20, 30, 40, 50]
}

pub fn apply_cap_test() {
  assert persevero.linear_backoff(5, 5)
    |> persevero.apply_cap(15)
    |> yielder.take(5)
    |> yielder.to_list
    == [5, 10, 15, 15, 15]
}

// Test prepare stream ---------------------------------------------------------

pub fn max_attempts_prepare_wait_stream_test() {
  assert persevero.linear_backoff(5, 5)
    |> persevero.prepare_wait_stream(persevero.MaxAttempts(3))
    |> yielder.to_list
    == [0, 5, 10]
}

pub fn prepare_wait_stream_expiry_exact_fits_perfectly_test() {
  // When remaining time exactly matches next wait time, no truncation needed
  assert persevero.constant_backoff(5)
    |> persevero.prepare_wait_stream(persevero.Expiry(10, persevero.Exact))
    |> yielder.to_list
    == [0, 5, 5]
}

pub fn prepare_wait_stream_expiry_exact_with_truncation_test() {
  // When next wait time exceeds remaining time, it gets truncated to fit
  assert persevero.constant_backoff(5)
    |> persevero.prepare_wait_stream(persevero.Expiry(11, persevero.Exact))
    |> yielder.to_list
    == [0, 5, 5, 1]
}

pub fn prepare_wait_stream_expiry_spillover_fits_perfectly_test() {
  // When remaining time exactly matches next wait time, full wait is used
  assert persevero.constant_backoff(5)
    |> persevero.prepare_wait_stream(persevero.Expiry(10, persevero.Spillover))
    |> yielder.to_list
    == [0, 5, 5]
}

pub fn prepare_wait_stream_expiry_spillover_exceeds_limit_test() {
  // When next wait time would exceed limit, Spillover allows the full wait
  assert persevero.constant_backoff(5)
    |> persevero.prepare_wait_stream(persevero.Expiry(11, persevero.Spillover))
    |> yielder.to_list
    == [0, 5, 5, 5]
}
