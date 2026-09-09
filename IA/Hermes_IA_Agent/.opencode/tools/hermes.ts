import { tool } from "@opencode-ai/plugin"
import path from "node:path"

export default tool({
  description:
    "Delegate a task to the isolated Hermes agent. Hermes can only access its dedicated workspace and persistent state.",
  args: {
    prompt: tool.schema.string().min(1).describe("Complete task or question for Hermes"),
  },
  async execute({ prompt }) {
    const project = path.resolve(import.meta.dir, "../..")
    const process = Bun.spawn(
      [
        "docker",
        "compose",
        "--project-directory",
        project,
        "-f",
        path.join(project, "compose.yaml"),
        "run",
        "--rm",
        "--no-deps",
        "hermes",
        "chat",
        "-q",
        prompt,
      ],
      {
        cwd: project,
        stdout: "pipe",
        stderr: "pipe",
      },
    )

    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ])

    if (exitCode !== 0) {
      throw new Error(stderr.trim() || `Hermes exited with code ${exitCode}`)
    }

    return stdout.trim() || stderr.trim() || "Hermes returned no output."
  },
})
