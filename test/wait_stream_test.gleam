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
