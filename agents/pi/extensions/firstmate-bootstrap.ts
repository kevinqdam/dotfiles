import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const firstmateRoot = resolve(
  process.env.FIRSTMATE_ROOT || `${process.env.HOME}/dev/firstmate`,
);
const firstmateHome = resolve(
  process.env.FIRSTMATE_HOME || `${process.env.HOME}/.local/share/firstmate`,
);
const active = process.env.FM_FIRSTMATE_ACTIVE === "1";
const cwd = resolve(process.cwd());
const inFirstmateRoot = (() => {
  const rel = relative(firstmateRoot, cwd);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
})();

async function loadFirstmateExtension(pi: ExtensionAPI, name: string): Promise<void> {
  const path = resolve(firstmateRoot, ".pi/extensions", name);
  if (!existsSync(path)) return;
  const loaded = await import(pathToFileURL(path).href);
  if (typeof loaded.default === "function") await loaded.default(pi);
}

export default async function (pi: ExtensionAPI) {
  pi.registerCommand("firstmate", {
    description: "Activate Firstmate for the current repository",
    handler: async (_args, ctx) => {
      if (process.env.FM_FIRSTMATE_ACTIVE === "1") {
        ctx.ui.notify("Firstmate is already active for this session.", "info");
        return;
      }
      const git = await pi.exec("git", ["-C", cwd, "rev-parse", "--show-toplevel"]);
      if (git.code !== 0) {
        ctx.ui.notify("Firstmate requires a Git repository as the current project.", "error");
        return;
      }
      process.env.FM_FIRSTMATE_ACTIVE = "1";
      process.env.FM_ROOT_OVERRIDE = firstmateRoot;
      process.env.FM_HOME = firstmateHome;
      ctx.ui.notify(`Activating Firstmate for ${cwd}; reloading Pi...`, "info");
      await ctx.reload();
    },
  });

  if (!active) return;

  process.env.FM_ROOT_OVERRIDE = firstmateRoot;
  process.env.FM_HOME = firstmateHome;

  if (!inFirstmateRoot) {
    await loadFirstmateExtension(pi, "fm-primary-turnend-guard.ts");
    await loadFirstmateExtension(pi, "fm-primary-pi-watch.ts");
    await loadFirstmateExtension(pi, "fm-calm.ts");
  }

  pi.on("resources_discover", async () => ({
    skillPaths: [resolve(firstmateRoot, ".agents/skills")],
  }));

  pi.on("before_agent_start", async (event) => {
    const agentsPath = resolve(firstmateRoot, "AGENTS.md");
    if (!existsSync(agentsPath)) return;
    const instructions = readFileSync(agentsPath, "utf8");
    return {
      systemPrompt:
        `${event.systemPrompt}\n\n` +
        `# Firstmate instructions\n\n${instructions}`,
    };
  });

  pi.on("session_start", (_event, context) => {
    context.ui.notify(`Firstmate active: ${firstmateRoot}`, "info");
  });
}
