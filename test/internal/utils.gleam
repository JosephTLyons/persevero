import bigben/clock
import bigben/fake_clock
import gleam/time/duration

pub fn advance_fake_clock_ms(
  clock clock: fake_clock.FakeClock,
  by by: Int,
) -> Nil {
  let duration = duration.milliseconds(by)
  clock |> fake_clock.advance(duration)
}

pub fn build_fake_operation(
  fake_clock: fake_clock.FakeClock,
  fake_response: fn(Int) -> #(Int, Result(a, b)),
) -> fn(Int, clock.Clock) -> #(Int, Result(a, b)) {
  fn(attempt, _) {
    let response = fake_response(attempt)
    advance_fake_clock_ms(fake_clock, response.0)
    response
  }
}
