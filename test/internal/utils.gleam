import bigben/fake_clock
import gleam/time/duration

pub fn fake_wait(_: Int) -> Nil {
  Nil
}

pub fn advance_fake_clock(clock clock: fake_clock.FakeClock, by by: Int) -> Nil {
  let duration = duration.milliseconds(by)
  clock |> fake_clock.advance(duration)
}
