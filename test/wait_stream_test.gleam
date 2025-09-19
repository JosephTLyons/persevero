import bigben/clock
import bigben/fake_clock
import gleam/int
import gleam/pair
import gleam/yielder
import internal/utils.{advance_fake_clock_ms, fake_wait}
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
  let fake_clock = fake_clock.new()
  assert persevero.linear_backoff(5, 5)
    |> persevero.prepare_wait_stream(
      advance_fake_clock_ms(fake_clock, _),
      persevero.MaxAttempts(3),
      fn(_, _) { #(1, Ok(Nil)) },
      clock.from_fake(fake_clock),
    )
    |> yielder.map(fn(tuple) { tuple.0 })
    |> yielder.to_list
    == [0, 5, 10]
}
// pub fn prepare_wait_stream_expiry_exact_fits_perfectly_test() {
//   // When remaining time exactly matches next wait time, no truncation needed
//   let fake_clock = fake_clock.new()
//   assert persevero.constant_backoff(5)
//     |> persevero.prepare_wait_stream(
//       advance_fake_clock_ms(fake_clock, _),
//       persevero.Expiry(10, persevero.Exact),
//       fn(_, _) { #(1, Ok(Nil)) },
//       clock.from_fake(fake_clock),
//     )
//     |> yielder.map(fn(tuple) { tuple.0 })
//     |> yielder.to_list
//     == [0, 5, 5]
// }
// pub fn prepare_wait_stream_expiry_exact_with_truncation_test() {
//   // When next wait time exceeds remaining time, it gets truncated to fit
//   assert persevero.constant_backoff(5)
//     |> persevero.prepare_wait_stream(persevero.Expiry(11, persevero.Exact))
//     |> yielder.map(pair.first)
//     |> yielder.to_list
//     == [0, 5, 5, 1]
// }

// pub fn prepare_wait_stream_expiry_spillover_fits_perfectly_test() {
//   // When remaining time exactly matches next wait time, full wait is used
//   assert persevero.constant_backoff(5)
//     |> persevero.prepare_wait_stream(persevero.Expiry(10, persevero.Spillover))
//     |> yielder.map(pair.first)
//     |> yielder.to_list
//     == [0, 5, 5]
// }

// pub fn prepare_wait_stream_expiry_spillover_exceeds_limit_test() {
//   // When next wait time would exceed limit, Spillover allows the full wait
//   assert persevero.constant_backoff(5)
//     |> persevero.prepare_wait_stream(persevero.Expiry(21, persevero.Spillover))
//     |> yielder.map(fn(tuple) { tuple.0 })
//     |> yielder.to_list
//     == [0, 5, 5, 5, 5, 5]
// }

// pub fn prepare_wait_stream_tracks_attempts_test() {
//   // Verify that attempts are correctly indexed starting from 0
//   assert persevero.constant_backoff(10)
//     |> persevero.prepare_wait_stream(persevero.MaxAttempts(4))
//     |> yielder.map(pair.second)
//     // Get the attempt number
//     |> yielder.to_list
//     == [0, 1, 2, 3]
// }
