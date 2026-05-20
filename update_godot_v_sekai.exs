#!/usr/bin/env elixir

argv = System.argv()

if Enum.any?(argv, &(&1 in ["-h", "--help"])) do
  IO.puts("""
  Usage: elixir #{__ENV__.file} [--help|-h] [--dry-run|--no-push|-n]

  Compiles all branches in gitassembly and pushes to V-Sekai-fire/multiplayer-fabric-godot.

  --help, -h       Display help
  --dry-run, -n    Do not push.
  """)
  System.halt(0)
end

dry_run = Enum.any?(argv, &(&1 in ["-n", "--no-push", "--dry-run"]))

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

merge_remote = "v-sekai-multiplayer-fabric"

add_remote.(merge_remote, "https://github.com/v-sekai-multiplayer-fabric/godot.git")
add_remote.("opentelemetry-godot", "https://github.com/V-Sekai-fire/opentelemetry-godot.git")

original_branch = "main"

current_branch = String.trim(run!.("git", ["rev-parse", "--abbrev-ref", "HEAD"]))
if current_branch != original_branch do
  IO.puts("Failed to run merge script: not on #{original_branch} branch.")
  System.halt(1)
end

IO.puts("*** Working on assembling gitassembly")

has_changes =
  case System.cmd("git", ["diff", "--quiet", "HEAD"], stderr_to_stdout: true) do
    {_, 0} -> false
    _ -> true
  end

run!.("git", ["stash"])

merge_branch_base = "multiplayer-fabric-base"
merge_branch = "multiplayer-fabric"

run!.("git", ["checkout", original_branch, "--force"])
System.cmd("git", ["branch", "-D", merge_branch_base], stderr_to_stdout: true)
System.cmd("git", ["branch", "-D", merge_branch], stderr_to_stdout: true)
run!.("python3", ["./thirdparty/git-assembler", "-av", "--recreate", "--config", "gitassembly"])

if not dry_run do
  run!.("git", ["checkout", merge_branch_base, "-f"])
  run!.("git", ["push", merge_remote, merge_branch_base, "-f"])

  run!.("git", ["checkout", merge_branch, "-f"])
  run!.("git", ["commit", "--allow-empty", "-m", "Merge branch '#{merge_branch}'"])
  run!.("git", ["push", merge_remote, merge_branch, "-f"])

  run!.("git", ["checkout", original_branch, "--force"])
  System.cmd("git", ["branch", "-D", merge_branch_base], stderr_to_stdout: true)
  System.cmd("git", ["branch", "-D", merge_branch], stderr_to_stdout: true)
else
  run!.("git", ["checkout", original_branch, "--force"])
  IO.puts("#{merge_branch_base} and #{merge_branch} were created and are ready to push.")
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
