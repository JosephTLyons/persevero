import gleam/http/request
import gleam/httpc
import gleam/io
import persevero.{Spillover}

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response = {
    use <- persevero.execute(
      wait_stream: persevero.constant_backoff(100),
      allow: persevero.all_errors,
      mode: persevero.Expiry(10_000, Spillover),
    )

    httpc.send(request)
  }

  case response {
    Ok(response) if response.status == 200 ->
      io.println("Give me #prawducks. 😃")
    _ -> io.println("Guess I'll dev on Linux. 😔")
  }
}
