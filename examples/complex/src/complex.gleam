import gleam/http/request
import gleam/httpc
import gleam/io
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response =
    persevero.custom_backoff(wait_time: 1000, next_wait_time: fn(previous) {
      { previous + 100 } * 2
    })
    |> persevero.apply_multiplier(3)
    |> persevero.apply_jitter(20)
    |> persevero.apply_cap(10_000)
    |> persevero.apply_constant(7)
    |> persevero.execute(
      allow: fn(error) {
        case error {
          httpc.InvalidUtf8Response -> True
          _ -> False
        }
      },
      mode: persevero.MaxAttempts(10),
      operation: fn() { httpc.send(request) },
    )

  case response {
    Ok(response) if response.status == 200 ->
      io.println("Give me #prawducks. 😃")
    _ -> io.println("Guess I'll dev on Linux. 😔")
  }
}
