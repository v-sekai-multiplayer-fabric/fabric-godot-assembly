#!/usr/bin/env elixir

argv = System.argv()

if Enum.any?(argv, &(&1 in ["-h", "--help"])) do
  IO.puts("""
  Usage: elixir #{__ENV__.file} [--help|-h] [--dry-run|--no-push|-n]

  --help, -h       Display help
  --dry-run, -n    Do not push.
  """)
  System.halt(0)
end

dry_run = Enum.any?(argv, &(&1 in ["-n", "--no-push", "--dry-run"]))

merge_remote = "v-sekai-multiplayer-fabric"
merge_remote_url = "https://github.com/v-sekai-multiplayer-fabric/godot.git"
opentelemetry_remote = "opentelemetry-godot"
opentelemetry_remote_url = "https://github.com/V-Sekai-fire/opentelemetry-godot.git"
original_branch = "main"
merge_branch = "multiplayer-fabric"
assembler_path = "./thirdparty/git-assembler"
assembler_config = "gitassembly"

run! = fn cmd, args ->
  case System.cmd(cmd, args, stderr_to_stdout: true) do
    {output, 0} ->
      if output != "", do: IO.puts(output)
      output
    {output, code} ->
      IO.puts(output)
      raise "Command failed (exit #{code}): #{cmd} #{Enum.join(args, " ")}"
  end
end

add_remote = fn name, url ->
  System.cmd("git", ["remote", "add", name, url], stderr_to_stdout: true)
  System.cmd("git", ["remote", "set-url", name, url], stderr_to_stdout: true)
  run!.("git", ["fetch", name])
end

IO.puts("Checkout remotes")

add_remote.(merge_remote, merge_remote_url)
add_remote.(opentelemetry_remote, opentelemetry_remote_url)

current_branch = String.trim(run!.("git", ["rev-parse", "--abbrev-ref", "HEAD"]))
if current_branch != original_branch do
  IO.puts("Failed to run merge script: not on #{original_branch} branch.")
  System.halt(1)
end

IO.puts("*** Working on assembling #{assembler_config}")

has_changes =
  case System.cmd("git", ["diff", "--quiet", "HEAD"], stderr_to_stdout: true) do
    {_, 0} -> false
    _ -> true
  end

run!.("git", ["stash"])

run!.("git", ["checkout", original_branch, "--force"])
System.cmd("git", ["branch", "-D", merge_branch], stderr_to_stdout: true)
run!.("python3", [assembler_path, "-av", "--recreate", "--config", assembler_config])

tag_name =
  "v" <>
    (DateTime.utc_now()
     |> Calendar.strftime("%Y.%m.%d.%H%M")) <>
    "-#{merge_branch}"

if not dry_run do
  run!.("git", ["checkout", merge_branch, "-f"])
  run!.("git", ["commit", "--allow-empty", "-m", "Merge branch '#{merge_branch}'"])
  run!.("git", ["push", merge_remote, merge_branch, "-f"])

  run!.("git", ["tag", "-a", tag_name, "-m", "#{merge_branch} #{tag_name}"])
  run!.("git", ["push", merge_remote, tag_name])

  run!.("git", ["checkout", original_branch, "--force"])
  System.cmd("git", ["branch", "-D", merge_branch], stderr_to_stdout: true)
else
  run!.("git", ["checkout", original_branch, "--force"])
  IO.puts("#{merge_branch} was created and is ready to push.")
  IO.puts("Would tag as #{tag_name}.")
end

IO.puts("ALL DONE. ----------------------------")

if has_changes do
  IO.puts("""
  Note that uncommitted changes may have been stashed. Run
      git stash apply
  to re-apply them.
  """)
  run!.("git", ["stash", "list"])
end
