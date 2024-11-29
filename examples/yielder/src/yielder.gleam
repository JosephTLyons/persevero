import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/yielder
import persevero

pub fn main() {
  let assert Ok(request) = request.to("https://www.apple.com")

  let response = {
    use <- persevero.execute(
      wait_stream: yielder.repeat(5)
        |> yielder.intersperse(10)
        |> yielder.cycle,
      allow: persevero.all_errors,
      mode: persevero.MaxAttempts(100),
    )

    httpc.send(request)
  }

  case response {
    Ok(response) if response.status == 200 -> io.debug("Give me #prawducks. 😃")
    _ -> io.debug("Guess I'll dev on Linux. 😔")
  }
}
