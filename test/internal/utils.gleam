import bigben/fake_clock
import birl/duration

pub fn fake_wait(_: Int) -> Nil {
  Nil
}

pub fn advance_fake_clock(clock clock: fake_clock.FakeClock, by by: Int) -> Nil {
  let duration = duration.milli_seconds(by)
  clock |> fake_clock.advance(duration)
}
