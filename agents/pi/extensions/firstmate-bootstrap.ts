import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const hasEnvironmentValue = (name: string): boolean =>
  Object.prototype.hasOwnProperty.call(process.env, name);

const cwd = resolve(process.cwd());
const primaryRoot = resolve(
  process.env.FIRSTMATE_ROOT || `${process.env.HOME}/dev/firstmate`,
);
const canonicalHome = resolve(
  process.env.FIRSTMATE_HOME || `${process.env.HOME}/.local/share/firstmate`,
);

// An explicitly supplied FM_ROOT_OVERRIDE, including the empty value used by
// secondmate launches, is authoritative. An empty secondmate override means
// that its checked-out working directory is the code root for this process.
const codeRoot = hasEnvironmentValue("FM_ROOT_OVERRIDE")
  ? process.env.FM_ROOT_OVERRIDE
    ? resolve(process.env.FM_ROOT_OVERRIDE)
    : cwd
  : primaryRoot;
const activeHome = process.env.FM_HOME
  ? resolve(process.env.FM_HOME)
  : canonicalHome;
const active = process.env.FM_FIRSTMATE_ACTIVE === "1";
const inPrimaryRoot = (() => {
  const rel = relative(primaryRoot, cwd);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
})();

function applyPrimaryDefaults(): void {
  if (!hasEnvironmentValue("FM_ROOT_OVERRIDE")) {
    process.env.FM_ROOT_OVERRIDE = primaryRoot;
  }
  if (!hasEnvironmentValue("FM_HOME")) {
    process.env.FM_HOME = canonicalHome;
  }
}

// A direct Pi launch from the primary Firstmate checkout is already a
// Firstmate session boundary. Set the canonical home before any command can
// load a script, while leaving explicit secondmate environment overrides alone.
if (active || (!hasEnvironmentValue("FM_HOME") && inPrimaryRoot)) {
  applyPrimaryDefaults();
}

async function loadFirstmateExtension(pi: ExtensionAPI, name: string): Promise<void> {
  const path = resolve(codeRoot, ".pi/extensions", name);
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
      applyPrimaryDefaults();
      process.env.FM_FIRSTMATE_ACTIVE = "1";
      ctx.ui.notify(`Activating Firstmate for ${cwd}; reloading Pi...`, "info");
      await ctx.reload();
    },
  });

  if (!active) return;

  applyPrimaryDefaults();

  if (!inPrimaryRoot) {
    await loadFirstmateExtension(pi, "fm-primary-turnend-guard.ts");
    await loadFirstmateExtension(pi, "fm-primary-pi-watch.ts");
    await loadFirstmateExtension(pi, "fm-calm.ts");
  }

  pi.on("resources_discover", async () => ({
    skillPaths: [resolve(codeRoot, ".agents/skills")],
  }));

  pi.on("before_agent_start", async (event) => {
    const agentsPath = resolve(codeRoot, "AGENTS.md");
    if (!existsSync(agentsPath)) return;
    const instructions = readFileSync(agentsPath, "utf8");
    return {
      systemPrompt:
        `${event.systemPrompt}\n\n` +
        `# Firstmate instructions\n\n${instructions}`,
    };
  });

  pi.on("session_start", (_event, context) => {
    context.ui.notify(`Firstmate active: ${activeHome}`, "info");
  });
}
