import gleam/time/timestamp
import persevero.{duration_ms}

pub fn duration_test() {
  let assert Ok(t_1) = timestamp.parse_rfc3339("1990-04-12T00:00:00.000Z")
  let assert Ok(t_2) = timestamp.parse_rfc3339("1990-04-12T00:00:00.000Z")
  assert duration_ms(t_1, t_2) == 0

  let assert Ok(t_1) = timestamp.parse_rfc3339("1990-04-12T00:00:00.000Z")
  let assert Ok(t_2) = timestamp.parse_rfc3339("1990-04-12T00:00:00.010Z")
  assert duration_ms(t_1, t_2) == 10

  let assert Ok(t_1) = timestamp.parse_rfc3339("1990-04-12T00:00:00.000Z")
  let assert Ok(t_2) = timestamp.parse_rfc3339("1990-04-12T00:00:00.020Z")
  assert duration_ms(t_1, t_2) == 20
}
