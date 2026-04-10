import Foundation
import XhammerCore

let args = Array(CommandLine.arguments.dropFirst())

guard !args.isEmpty else {
  Commands.printHelp()
  exit(0)
}

let commandName = args[0]
let commandArgs = Array(args.dropFirst())

// Handle --help / -h
if commandName == "--help" || commandName == "-h" || commandName == "help" {
  Commands.printHelp()
  exit(0)
}

guard let command = Commands.find(named: commandName) else {
  fputs("error: unknown command '\(commandName)'\n\n", stderr)
  Commands.printHelp()
  exit(1)
}

guard commandArgs.count >= command.minArgs else {
  fputs("error: '\(commandName)' requires at least \(command.minArgs) argument(s)\n", stderr)
  fputs("usage: xhammer \(command.usage)\n", stderr)
  exit(1)
}

do {
  let request = try command.build(commandArgs)
  let client = DaemonClient()
  let response = try client.send(request)

  let output = OutputFormatter.format(response: response, method: request.method)
  print(output)

  exit(response.ok ? 0 : 1)
} catch {
  fputs("error: \(error.localizedDescription)\n", stderr)
  exit(1)
}
