import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { execFile } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import test from "node:test";
import { URL } from "node:url";
import { promisify } from "node:util";

const repositoryFile = (path) => new URL(`../${path}`, import.meta.url);
const execFileAsync = promisify(execFile);
const deliveryWrapper = repositoryFile(
  ".opencode/scripts/github-delivery.sh",
).pathname;
const dependencyWrapper = repositoryFile(
  ".opencode/scripts/dependency-update.sh",
).pathname;

async function createDeliveryFixture(t, { workflow = true } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "delivery-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await execFileAsync("git", ["init", "-b", "main"], { cwd: directory });
  await execFileAsync("git", ["config", "user.name", "Test"], {
    cwd: directory,
  });
  await execFileAsync("git", ["config", "user.email", "test@example.com"], {
    cwd: directory,
  });
  await writeFile(path.join(directory, "README.md"), "fixture\n");
  await mkdir(path.join(directory, ".opencode", "scripts"), {
    recursive: true,
  });
  const fixtureWrapper = path.join(
    directory,
    ".opencode",
    "scripts",
    "github-delivery.sh",
  );
  await writeFile(fixtureWrapper, await readFile(deliveryWrapper, "utf8"));
  await writeFile(
    path.join(directory, ".opencode", "scripts", "dependency-update.sh"),
    await readFile(dependencyWrapper, "utf8"),
  );
  if (workflow) {
    await mkdir(path.join(directory, ".github", "workflows"), {
      recursive: true,
    });
    await writeFile(
      path.join(directory, ".github", "workflows", "quality.yml"),
      "name: Quality\n",
    );
  }
  await execFileAsync("git", ["add", "."], { cwd: directory });
  await execFileAsync("git", ["commit", "-m", "test: fixture"], {
    cwd: directory,
  });

  const remoteDirectory = await mkdtemp(
    path.join(os.tmpdir(), "delivery-remote-"),
  );
  t.after(() => rm(remoteDirectory, { recursive: true, force: true }));
  await execFileAsync(
    "git",
    ["init", "--bare", "--initial-branch=main", remoteDirectory],
    { cwd: directory },
  );
  await execFileAsync(
    "git",
    ["push", `file://${remoteDirectory}`, "main:main"],
    { cwd: directory },
  );
  await execFileAsync(
    "git",
    ["remote", "add", "origin", "https://github.com/owner/repository.git"],
    { cwd: directory },
  );

  const binaryDirectory = await mkdtemp(
    path.join(os.tmpdir(), "delivery-bin-"),
  );
  t.after(() => rm(binaryDirectory, { recursive: true, force: true }));
  const stateFile = path.join(binaryDirectory, "merged");
  const sleep = path.join(binaryDirectory, "sleep");
  await writeFile(sleep, "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
  const npm = path.join(binaryDirectory, "npm");
  await writeFile(
    npm,
    '#!/usr/bin/env bash\nprintf \'%s\\n\' "$@" >>"${GH_STATE_FILE}.npm"\n',
    { mode: 0o755 },
  );
  const gh = path.join(binaryDirectory, "gh");
  await writeFile(
    gh,
    `#!/usr/bin/env bash
set -eu
head_sha="$(git rev-parse HEAD)"
case "\${GH_SCENARIO:-open}:\${1:-}:\${2:-}" in
  auth-fail:auth:status) exit 1 ;;
  *:auth:status) exit 0 ;;
  closed:issue:view) printf '%s\\n' '{"state":"CLOSED","title":"Closed"}' ;;
  happy:issue:view)
    if [[ " $* " == *" --jq "* ]]; then printf '%s\\n' 'CLOSED'; else printf '%s\\n' '{"state":"OPEN","title":"Test issue"}'; fi
    ;;
  *:issue:view) printf '%s\\n' '{"state":"OPEN","title":"Test issue"}' ;;
  review:pr:view) printf '{"number":7,"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"main","mergedAt":null,"statusCheckRollup":[{"name":"Quality","conclusion":"SUCCESS"}]}\\n' "$head_sha" ;;
  red:pr:view) printf '{"number":7,"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"APPROVED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"main","mergedAt":null,"statusCheckRollup":[{"name":"Quality","conclusion":"FAILURE"}]}\\n' "$head_sha" ;;
  wrong-base:pr:view) printf '{"number":7,"state":"MERGED","mergeable":"UNKNOWN","reviewDecision":"APPROVED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"release","mergedAt":"2026-09-15T12:00:00Z","statusCheckRollup":[{"name":"Quality","conclusion":"SUCCESS"}]}\\n' "$head_sha" ;;
  stale-main:pr:view) printf '{"number":7,"state":"MERGED","mergeable":"UNKNOWN","reviewDecision":"APPROVED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"main","mergedAt":"2026-09-15T12:00:00Z","mergeCommit":{"oid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"statusCheckRollup":[{"name":"Quality","conclusion":"SUCCESS"}]}\\n' "$head_sha" ;;
  red:pr:checks)
    [[ " $* " == *" --watch "* ]] && exit 1
    printf '%s\\n' '[{"name":"Quality","state":"FAILURE","bucket":"fail"}]'
    ;;
  review:pr:checks) printf '%s\\n' '[{"name":"Quality","state":"SUCCESS","bucket":"pass"}]' ;;
  delayed:pr:view)
    count_file="\${GH_STATE_FILE}.count"
    count=0
    [[ -f "$count_file" ]] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" >"$count_file"
    rollup='[{"name":"Fast","conclusion":"SUCCESS"}]'
    [[ "$count" -ge 4 ]] && rollup='[{"name":"Fast","conclusion":"SUCCESS"},{"name":"Delayed","conclusion":"SUCCESS"}]'
    printf '{"number":7,"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"APPROVED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"main","mergedAt":null,"statusCheckRollup":%s}\\n' "$head_sha" "$rollup"
    ;;
  delayed:pr:checks)
    count="$(cat "\${GH_STATE_FILE}.count")"
    [[ "$count" -ge 4 ]] || exit 1
    printf '%s\\n' '[{"name":"Fast","state":"SUCCESS","bucket":"pass"},{"name":"Delayed","state":"SUCCESS","bucket":"pass"}]'
    ;;
  post-late:pr:view)
    count_file="\${GH_STATE_FILE}.count"
    count=0
    [[ -f "$count_file" ]] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" >"$count_file"
    rollup='[{"name":"Fast","conclusion":"SUCCESS"}]'
    [[ -f "\${GH_STATE_FILE}.watched" ]] && rollup='[{"name":"Fast","conclusion":"SUCCESS"},{"name":"PostWatch","conclusion":"SUCCESS"}]'
    printf '{"number":7,"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"APPROVED","headRefName":"feature/1-test","headRefOid":"%s","baseRefName":"main","mergedAt":null,"statusCheckRollup":%s}\\n' "$head_sha" "$rollup"
    ;;
  post-late:pr:checks)
    [[ " $* " == *" --watch "* ]] && touch "\${GH_STATE_FILE}.watched"
    printf '%s\\n' '[{"name":"Fast","state":"SUCCESS","bucket":"pass"},{"name":"PostWatch","state":"SUCCESS","bucket":"pass"}]'
    ;;
  post-late:pr:merge) exit 0 ;;
  happy:pr:create) printf '%s\\n' 'https://github.com/owner/repository/pull/7' ;;
  happy:pr:view)
    count_file="\${GH_STATE_FILE}.count"
    count=0
    [[ -f "$count_file" ]] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" >"$count_file"
    rollup='[{"name":"Quality","conclusion":"SUCCESS"}]'
    [[ "$count" -eq 1 ]] && rollup='[]'
    merged_at='null'
    [[ -f "$GH_STATE_FILE" ]] && merged_at='"2026-09-15T12:00:00Z"'
    merge_commit='null'
    if [[ -f "$GH_STATE_FILE" ]]; then
      merge_oid="$(cat "\${GH_STATE_FILE}.commit")"
      merge_commit="$(printf '{"oid":"%s"}' "$merge_oid")"
    fi
    state='OPEN'
    [[ -f "$GH_STATE_FILE" ]] && state='MERGED'
    printf '{"number":7,"state":"%s","mergeable":"MERGEABLE","reviewDecision":"APPROVED","headRefName":"feature/1-test-issue","headRefOid":"%s","baseRefName":"main","mergedAt":%s,"mergeCommit":%s,"statusCheckRollup":%s}\\n' "$state" "$head_sha" "$merged_at" "$merge_commit" "$rollup"
    ;;
  happy:pr:checks) printf '%s\\n' '[{"name":"Quality","state":"SUCCESS","bucket":"pass"}]' ;;
  happy:pr:merge)
    touch "$GH_STATE_FILE"
    branch="$(git branch --show-current)"
    tree="$(git rev-parse "HEAD^{tree}")"
    parent="$(git rev-parse origin/main)"
    merge_commit="$(printf '%s\\n' 'test: squash delivery' | git commit-tree "$tree" -p "$parent")"
    printf '%s\\n' "$merge_commit" >"\${GH_STATE_FILE}.commit"
    git push origin "$merge_commit:main" >/dev/null
    git push origin --delete "$branch" >/dev/null
    ;;
  happy:issue:close) exit 0 ;;
  *) exit 2 ;;
esac
`,
    { mode: 0o755 },
  );

  return {
    directory,
    environment: {
      ...process.env,
      PATH: `${binaryDirectory}:${process.env.PATH}`,
      GH_STATE_FILE: stateFile,
      GIT_CONFIG_COUNT: "1",
      GIT_CONFIG_KEY_0: `url.file://${remoteDirectory}/.insteadOf`,
      GIT_CONFIG_VALUE_0: "https://github.com/owner/repository.git",
    },
    wrapper: fixtureWrapper,
  };
}

async function runDelivery(fixture, scenario, ...arguments_) {
  return execFileAsync("bash", [fixture.wrapper, ...arguments_], {
    cwd: fixture.directory,
    env: { ...fixture.environment, GH_SCENARIO: scenario },
  });
}

test("keeps expensive MCP tools deny-by-default with env-scoped Context7 auth", async () => {
  const config = JSON.parse(
    await readFile(repositoryFile("opencode.json"), "utf8"),
  );

  assert.equal(config.default_agent, "orchestrator");
  assert.equal(config.subagent_depth, 1);
  assert.equal(config.share, "disabled");
  assert.equal(config.permission["playwright_*"], "deny");
  assert.equal(config.permission["context7_*"], "deny");
  assert.deepEqual(Object.keys(config.mcp).sort(), ["context7", "playwright"]);
  assert.equal(config.mcp.playwright.type, "local");
  assert.deepEqual(config.mcp.playwright.command, [
    "npx",
    "-y",
    "@playwright/mcp@0.0.80",
    "--isolated",
    "--output-dir",
    ".artifacts/playwright",
  ]);
  assert.equal(config.mcp.context7.type, "remote");
  assert.equal(config.mcp.context7.url, "https://mcp.context7.com/mcp");
  assert.ok(!("headers" in config.mcp.playwright));
  // Context7 is the deliberate exception: the auth header is required, but
  // only as an environment reference — never a stored secret.
  assert.deepEqual(config.mcp.context7.headers, {
    CONTEXT7_API_KEY: "{env:CONTEXT7_API_KEY}",
  });
  for (const forbidden of [
    "gh_grep",
    "github",
    "filesystem",
    "memory",
    "sequential",
    "sequential-thinking",
  ]) {
    assert.ok(!(forbidden in config.mcp));
  }
  assert.ok(!("gh_grep" in config.mcp.context7));
  assert.deepEqual(config.watcher.ignore, [".artifacts/**"]);
  const gitignore = await readFile(repositoryFile(".gitignore"), "utf8");
  assert.match(gitignore, /^\/\.artifacts\/$/m);
});

test("uses one writer and inherited agent models", async () => {
  const agentDirectory = repositoryFile(".opencode/agents/");
  const agentFiles = (await readdir(agentDirectory)).filter((file) =>
    file.endsWith(".md"),
  );
  const agents = Object.fromEntries(
    await Promise.all(
      agentFiles.map(async (file) => [
        file,
        await readFile(new URL(file, agentDirectory), "utf8"),
      ]),
    ),
  );

  for (const [file, source] of Object.entries(agents)) {
    assert.doesNotMatch(source, /^model:/m, `${file} pins a model`);
  }

  for (const [file, source] of Object.entries(agents)) {
    assert.match(
      source,
      /^ {2}bash: deny$|^ {4}"\*": deny$/m,
      `${file} must not auto-approve arbitrary shell commands`,
    );
  }

  assert.match(
    agents["implementer.md"],
    /^ {2}edit:\n {4}"\*": allow\n {4}"\.git\/\*\*": deny$/m,
  );
  for (const [file, source] of Object.entries(agents)) {
    if (file !== "implementer.md") {
      assert.match(source, /^ {2}edit: deny$/m, `${file} must be read-only`);
    }
  }

  assert.match(agents["browser-qa.md"], /^ {2}playwright_\*: allow$/m);
  assert.match(
    agents["browser-qa.md"],
    /^ {2}playwright_browser_run_code_unsafe: deny$/m,
  );
  assert.doesNotMatch(agents["browser-qa.md"], /^ {4}".*test.*": allow$/m);

  for (const [file, source] of Object.entries(agents)) {
    if (file !== "browser-qa.md") {
      assert.doesNotMatch(
        source,
        /^ {2}playwright_\*: allow$/m,
        `${file} must not receive Playwright`,
      );
    }
  }

  const context7Agents = new Set([
    "architect.md",
    "implementer.md",
    "research-explorer.md",
    "test-debugger.md",
  ]);
  for (const [file, source] of Object.entries(agents)) {
    const assertion = context7Agents.has(file)
      ? assert.match
      : assert.doesNotMatch;
    assertion.call(
      assert,
      source,
      /^ {2}context7_\*: allow$/m,
      `${file} has an incorrect Context7 policy`,
    );
  }

  assert.doesNotMatch(
    agents["orchestrator.md"],
    /^ {4}"(?:git (?:fetch|pull|add|commit|switch|push)|gh (?:issue close|pr create|pr merge)).*": allow$/m,
  );
  assert.match(
    agents["orchestrator.md"],
    /^ {4}"bash \.opencode\/scripts\/github-delivery\.sh \*": allow$/m,
  );
  for (const file of ["orchestrator.md", "test-debugger.md"]) {
    for (const operator of [">", "<", "|", "&&", "||", ";", "$(", "`"]) {
      assert.ok(
        agents[file].includes(`    "*${operator}*": deny`),
        `${file} must deny shell operator ${operator} without relying on spaces`,
      );
    }
    assert.ok(
      agents[file].includes('    "*--output*": deny'),
      `${file} must deny Git's file-writing --output option`,
    );
  }
  for (const [file, source] of Object.entries(agents)) {
    assert.doesNotMatch(
      source,
      /^ {4}"git .*": allow$/m,
      `${file} exposes a direct Git command`,
    );
  }
  assert.match(agents["implementer.md"], /^ {4}"git commit\*": deny$/m);
  assert.match(agents["implementer.md"], /^ {4}"git push\*": deny$/m);
  assert.match(
    agents["implementer.md"],
    /^ {4}"bash \.opencode\/scripts\/dependency-update\.sh \*": allow$/m,
  );
  const implementerBash = agents["implementer.md"].match(
    /^ {2}bash:\n([\s\S]*?)^---$/m,
  )?.[1];
  assert.ok(implementerBash);
  assert.deepEqual(
    [...implementerBash.matchAll(/^ {4}"([^"]+)": allow$/gm)].map(
      (match) => match[1],
    ),
    ["bash .opencode/scripts/dependency-update.sh *"],
  );
  assert.ok(agents["implementer.md"].includes('    "*<*": deny'));

  const stepOf = (file) => Number(agents[file].match(/^steps: (\d+)$/m)?.[1]);
  assert.equal(stepOf("orchestrator.md"), 60);
  for (const file of [
    "architect.md",
    "research-explorer.md",
    "test-debugger.md",
    "reviewer.md",
    "browser-qa.md",
    "security-reviewer.md",
  ]) {
    const steps = stepOf(file);
    assert.ok(
      Number.isInteger(steps) && steps >= 20 && steps <= 35,
      `${file} steps must stay within 20-35`,
    );
  }
});

test("defines fail-closed implement delivery scenarios", async () => {
  const command = await readFile(
    repositoryFile(".opencode/commands/implement.md"),
    "utf8",
  );

  assert.match(command, /^agent: orchestrator$/m);
  assert.doesNotMatch(command, /^subtask:/m);
  assert.match(command, /exactly one GitHub issue URL/);
  assert.match(command, /compare the repository.*`origin`/);
  assert.match(command, /`gh auth status`/);
  assert.match(command, /confirm that it is open/);
  assert.match(command, /Require a clean working tree/);
  assert.match(command, /Require at least one GitHub Actions workflow/);
  assert.match(command, /Route every actionable finding back/);
  assert.match(command, /consolidated edit-only brief/);
  assert.match(command, /preliminary review.*executable inputs/s);
  assert.match(command, /github-delivery\.sh inspect/);
  assert.match(
    command,
    /Only then have `test-debugger` or the orchestrator run checks/,
  );
  assert.match(command, /Persistent zero checks.*blocks merge/);
  assert.match(command, /at most two evidence-backed repair rounds/);
  assert.match(command, /squash merge with branch deletion/);
  assert.match(command, /complete 60-second registration window/);
  assert.match(command, /30-second stable terminal check set/);
  assert.match(command, /merge <pr-number> <head-sha>/);
  assert.match(command, /switches locally to `main`/i);
  assert.match(command, /removes the exact validated local feature branch/);
});

test("keeps the GitHub delivery wrapper syntactically valid and fail-closed", async (t) => {
  await execFileAsync("bash", ["-n", deliveryWrapper]);
  await execFileAsync("bash", ["-n", dependencyWrapper]);

  const fixture = await createDeliveryFixture(t);
  await assert.rejects(
    runDelivery(fixture, "open", "prepare", "not-an-issue-url"),
    (error) =>
      error.stderr.includes("expected exactly one canonical GitHub issue URL"),
  );
  await writeFile(
    path.join(fixture.directory, "untracked file.txt"),
    "inspect me\n",
  );
  await writeFile(path.join(fixture.directory, ".gitkeep"), "");
  const inspection = await runDelivery(fixture, "open", "inspect");
  assert.match(inspection.stdout, /\?\?\tuntracked file\.txt/);
  assert.match(inspection.stdout, /\?\?\t\.gitkeep/);
  assert.match(inspection.stdout, /\+inspect me/);
  await assert.rejects(runDelivery(fixture, "open", "inspect", "--stat"));

  const source = await readFile(deliveryWrapper, "utf8");
  assert.match(source, /60-second registration window/);
  assert.match(source, /\.bucket == "pass"/);
  assert.match(source, /review_decision.*"CHANGES_REQUESTED"/s);
  assert.match(source, /--match-head-commit "\$2"/);
  assert.match(source, /git branch -D -- "\$head"/);
  assert.match(
    source,
    /explicit file list does not match every working-tree change/,
  );
  assert.doesNotMatch(source, /readlink -f|\$\{[A-Za-z_][A-Za-z0-9_]*,,\}/);
  assert.doesNotMatch(source, /find .*maxdepth/);
  assert.doesNotMatch(source, /git (?:reset|clean)|push .*--force/);
});

test("updates dependency classes only from a clean tree with scripts disabled", async (t) => {
  const clean = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-dependencies"], {
    cwd: clean.directory,
  });
  const cleanWrapper = path.join(
    clean.directory,
    ".opencode",
    "scripts",
    "dependency-update.sh",
  );
  await execFileAsync(
    "bash",
    [cleanWrapper, "add-dev", "npm", "typescript@latest"],
    { cwd: clean.directory, env: clean.environment },
  );
  assert.equal(
    await readFile(`${clean.environment.GH_STATE_FILE}.npm`, "utf8"),
    "install\n--save-dev\n--ignore-scripts\ntypescript@latest\n",
  );

  const batch = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-dependencies"], {
    cwd: batch.directory,
  });
  await execFileAsync(
    "bash",
    [
      path.join(
        batch.directory,
        ".opencode",
        "scripts",
        "dependency-update.sh",
      ),
      "batch",
      "npm",
      "remove:legacy-package",
      "add:runtime-package@latest",
      "add-dev:@types/runtime-package@latest",
    ],
    { cwd: batch.directory, env: batch.environment },
  );
  assert.equal(
    await readFile(`${batch.environment.GH_STATE_FILE}.npm`, "utf8"),
    "uninstall\n--ignore-scripts\nlegacy-package\n" +
      "install\n--ignore-scripts\nruntime-package@latest\n" +
      "install\n--save-dev\n--ignore-scripts\n@types/runtime-package@latest\n",
  );

  const dirty = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-dependencies"], {
    cwd: dirty.directory,
  });
  const dirtyWrapper = path.join(
    dirty.directory,
    ".opencode",
    "scripts",
    "dependency-update.sh",
  );
  await writeFile(path.join(dirty.directory, ".pnpmfile.cjs"), "throw 1\n");
  await assert.rejects(
    execFileAsync("bash", [dirtyWrapper, "add", "npm", "react@latest"], {
      cwd: dirty.directory,
      env: dirty.environment,
    }),
    (error) =>
      error.stderr.includes("first mutation on a clean feature branch"),
  );
  await assert.rejects(readFile(`${dirty.environment.GH_STATE_FILE}.npm`));

  const invalid = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-dependencies"], {
    cwd: invalid.directory,
  });
  await assert.rejects(
    execFileAsync(
      "bash",
      [
        path.join(
          invalid.directory,
          ".opencode",
          "scripts",
          "dependency-update.sh",
        ),
        "add",
        "npm",
        "--foreground-scripts",
      ],
      { cwd: invalid.directory, env: invalid.environment },
    ),
    (error) => error.stderr.includes("invalid package identifier"),
  );
});

test("rejects dirty trees, invalid auth, closed issues, and missing Actions", async (t) => {
  const issue = "https://github.com/owner/repository/issues/1";

  const dirty = await createDeliveryFixture(t);
  await writeFile(path.join(dirty.directory, "dirty.txt"), "dirty\n");
  await assert.rejects(runDelivery(dirty, "open", "prepare", issue), (error) =>
    error.stderr.includes("working tree must be clean"),
  );

  const invalidAuth = await createDeliveryFixture(t);
  await assert.rejects(runDelivery(invalidAuth, "auth-fail", "prepare", issue));

  const closed = await createDeliveryFixture(t);
  await assert.rejects(
    runDelivery(closed, "closed", "prepare", issue),
    (error) => error.stderr.includes("issue is not open"),
  );

  const noActions = await createDeliveryFixture(t, { workflow: false });
  await assert.rejects(
    runDelivery(noActions, "open", "prepare", issue),
    (error) => error.stderr.includes("GitHub Actions workflows are missing"),
  );
});

test("blocks red checks and requested review before merge", async (t) => {
  const fixture = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });

  await assert.rejects(runDelivery(fixture, "red", "wait-checks", "7"));
  const head = (
    await execFileAsync("git", ["rev-parse", "HEAD"], {
      cwd: fixture.directory,
    })
  ).stdout.trim();
  await assert.rejects(
    runDelivery(fixture, "review", "merge", "7", head),
    (error) => error.stderr.includes("pull request review is incomplete"),
  );
});

test("waits through delayed check registration", async (t) => {
  const fixture = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });

  await runDelivery(fixture, "delayed", "wait-checks", "7");
  assert.equal(
    await readFile(`${fixture.environment.GH_STATE_FILE}.count`, "utf8"),
    "11",
  );
});

test("re-discovers checks that register after the first watch", async (t) => {
  const fixture = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });

  await runDelivery(fixture, "post-late", "wait-checks", "7");
  assert.ok(
    Number(
      await readFile(`${fixture.environment.GH_STATE_FILE}.count`, "utf8"),
    ) > 7,
  );
});

test("direct merge repeats delayed-check discovery and stabilization", async (t) => {
  const fixture = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });
  const head = (
    await execFileAsync("git", ["rev-parse", "HEAD"], {
      cwd: fixture.directory,
    })
  ).stdout.trim();

  await runDelivery(fixture, "post-late", "merge", "7", head);
  assert.ok(
    Number(
      await readFile(`${fixture.environment.GH_STATE_FILE}.count`, "utf8"),
    ) > 7,
  );
});

test("blocks delivery with leftover changes or a merged PR outside main", async (t) => {
  const issue = "https://github.com/owner/repository/issues/1";
  const dirtyAfterCommit = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: dirtyAfterCommit.directory,
  });
  await writeFile(
    path.join(dirtyAfterCommit.directory, "feature.txt"),
    "feature\n",
  );
  await writeFile(
    path.join(dirtyAfterCommit.directory, "leftover.txt"),
    "leftover\n",
  );
  const headBeforeCommit = (
    await execFileAsync("git", ["rev-parse", "HEAD"], {
      cwd: dirtyAfterCommit.directory,
    })
  ).stdout.trim();
  await assert.rejects(
    runDelivery(
      dirtyAfterCommit,
      "open",
      "commit",
      "test: reject leftover changes",
      "feature.txt",
    ),
    (error) =>
      error.stderr.includes(
        "explicit file list does not match every working-tree change",
      ),
  );
  assert.equal(
    (
      await execFileAsync("git", ["rev-parse", "HEAD"], {
        cwd: dirtyAfterCommit.directory,
      })
    ).stdout.trim(),
    headBeforeCommit,
  );

  const wrongBase = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: wrongBase.directory,
  });
  await assert.rejects(
    runDelivery(wrongBase, "wrong-base", "cleanup", issue, "7"),
    (error) => error.stderr.includes("merged pull request base is not main"),
  );
});

test("keeps the feature branch when merged main lacks GitHub's merge commit", async (t) => {
  const fixture = await createDeliveryFixture(t);
  const issue = "https://github.com/owner/repository/issues/1";
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });

  await assert.rejects(
    runDelivery(fixture, "stale-main", "cleanup", issue, "7"),
    (error) =>
      error.stderr.includes("merge commit is not present in local main"),
  );
  assert.match(
    (
      await execFileAsync("git", ["branch", "--list", "feature/1-test"], {
        cwd: fixture.directory,
      })
    ).stdout,
    /feature\/1-test/,
  );
});

test("rejects wrapper tampering, recursive staging, and issue mismatch", async (t) => {
  const fixture = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: fixture.directory,
  });

  await assert.rejects(
    runDelivery(
      fixture,
      "open",
      "create-pr",
      "https://github.com/owner/repository/issues/2",
      "Test",
      "Closes #2",
    ),
    (error) =>
      error.stderr.includes("current branch does not belong to the issue"),
  );
  await writeFile(path.join(fixture.directory, "new.txt"), "new\n");
  await assert.rejects(
    runDelivery(fixture, "open", "commit", "test: reject directory", "."),
    (error) => error.stderr.includes("invalid staged path"),
  );

  await writeFile(
    fixture.wrapper,
    `${await readFile(fixture.wrapper, "utf8")}\n# tampered\n`,
  );
  await assert.rejects(runDelivery(fixture, "open", "push"), (error) =>
    error.stderr.includes("differs from trusted local main"),
  );
});

test("rejects sensitive paths and secret-like staged content", async (t) => {
  const sensitivePath = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: sensitivePath.directory,
  });
  await writeFile(
    path.join(sensitivePath.directory, ".NPMRC"),
    "registry=test\n",
  );
  await assert.rejects(
    runDelivery(
      sensitivePath,
      "open",
      "commit",
      "test: reject credential file",
      ".NPMRC",
    ),
    (error) => error.stderr.includes("refusing sensitive or escaping path"),
  );

  const secretContent = await createDeliveryFixture(t);
  await execFileAsync("git", ["switch", "-c", "feature/1-test"], {
    cwd: secretContent.directory,
  });
  const fakeApiKey = "abcdefghijkl" + "mnop";
  await writeFile(
    path.join(secretContent.directory, "config.txt"),
    `api_key="${fakeApiKey}"\n${"safe-value\n".repeat(200_000)}`,
  );
  await assert.rejects(
    runDelivery(
      secretContent,
      "open",
      "commit",
      "test: reject secret content",
      "config.txt",
    ),
    (error) => error.stderr.includes("untracked content resembles a secret"),
  );
  assert.equal(
    (
      await execFileAsync("git", ["diff", "--cached", "--name-only"], {
        cwd: secretContent.directory,
      })
    ).stdout,
    "",
  );
  await writeFile(
    path.join(secretContent.directory, "config.txt"),
    `api_key="${fakeApiKey}"\nsmall fixture\n`,
  );
  const secretInspection = await runDelivery(secretContent, "open", "inspect");
  assert.ok(!secretInspection.stdout.includes(fakeApiKey));
  assert.match(secretInspection.stdout, /REDACTED SECRET-LIKE DIFF LINE/);

  const contextSecret = await createDeliveryFixture(t);
  const committedPassword = "committed-" + "secret-value";
  await writeFile(
    path.join(contextSecret.directory, "context.txt"),
    `password="${committedPassword}"\nold value\n`,
  );
  await execFileAsync("git", ["add", "context.txt"], {
    cwd: contextSecret.directory,
  });
  await execFileAsync("git", ["commit", "-m", "test: add context fixture"], {
    cwd: contextSecret.directory,
  });
  await execFileAsync("git", ["switch", "-c", "feature/1-context"], {
    cwd: contextSecret.directory,
  });
  await writeFile(
    path.join(contextSecret.directory, "context.txt"),
    'password="${PASSWORD_FROM_ENV}"\nnew value\n',
  );
  const contextInspection = await runDelivery(contextSecret, "open", "inspect");
  assert.ok(!contextInspection.stdout.includes(committedPassword));
  assert.match(contextInspection.stdout, /REDACTED SECRET-LIKE DIFF LINE/);
  await runDelivery(
    contextSecret,
    "open",
    "commit",
    "fix: remove committed secret context",
    "context.txt",
  );

  const binarySecret = await createDeliveryFixture(t);
  await writeFile(
    path.join(binarySecret.directory, "binary.dat"),
    Buffer.from([0, 1, 2, 3]),
  );
  await execFileAsync("git", ["add", "binary.dat"], {
    cwd: binarySecret.directory,
  });
  await execFileAsync("git", ["commit", "-m", "test: add binary fixture"], {
    cwd: binarySecret.directory,
  });
  await execFileAsync("git", ["switch", "-c", "feature/1-binary"], {
    cwd: binarySecret.directory,
  });
  await writeFile(
    path.join(binarySecret.directory, "binary.dat"),
    Buffer.concat([
      Buffer.from([0, 1, 2, 3]),
      Buffer.from(`api_key="${fakeApiKey}"`),
    ]),
  );
  await assert.rejects(
    runDelivery(
      binarySecret,
      "open",
      "commit",
      "test: reject binary secret",
      "binary.dat",
    ),
    (error) => error.stderr.includes("staged blob content resembles a secret"),
  );
  assert.equal(
    (
      await execFileAsync("git", ["diff", "--cached", "--name-only"], {
        cwd: binarySecret.directory,
      })
    ).stdout,
    "",
  );
});

test("completes the mocked delivery happy path", async (t) => {
  const fixture = await createDeliveryFixture(t);
  const issue = "https://github.com/owner/repository/issues/1";

  await runDelivery(fixture, "happy", "prepare", issue);
  await writeFile(path.join(fixture.directory, "feature.txt"), "delivered\n");
  await runDelivery(
    fixture,
    "happy",
    "commit",
    "test: exercise delivery",
    "feature.txt",
  );
  await runDelivery(fixture, "happy", "push");
  await runDelivery(
    fixture,
    "happy",
    "create-pr",
    issue,
    "Test delivery",
    "Validation passed. Closes #1",
  );
  await runDelivery(fixture, "happy", "wait-checks", "7");
  const head = (
    await execFileAsync("git", ["rev-parse", "HEAD"], {
      cwd: fixture.directory,
    })
  ).stdout.trim();
  await runDelivery(fixture, "happy", "merge", "7", head);
  await runDelivery(fixture, "happy", "cleanup", issue, "7");

  assert.equal(
    (
      await execFileAsync("git", ["branch", "--show-current"], {
        cwd: fixture.directory,
      })
    ).stdout.trim(),
    "main",
  );
  assert.equal(
    (
      await execFileAsync("git", ["status", "--porcelain"], {
        cwd: fixture.directory,
      })
    ).stdout,
    "",
  );
  const expectedMain = await readFile(
    `${fixture.environment.GH_STATE_FILE}.commit`,
    "utf8",
  );
  assert.equal(
    (
      await execFileAsync("git", ["rev-parse", "HEAD"], {
        cwd: fixture.directory,
      })
    ).stdout.trim(),
    expectedMain.trim(),
  );
});
