// MAINFRAME's analysis-only shell-command normalizer for JavaScript consumers.
//
// This mirrors the bounded lexer in lib/agent_safety.sh. It never executes or
// rewrites caller input. Actual executable words are prefixed with ASCII RS so
// gate regexes can distinguish commands from prose in ordinary arguments.

export const EXECUTABLE_MARKER = "\x1e";

const CONTROL_WORDS = new Set([
  "if", "then", "elif", "else", "while", "until", "do", "fi", "done",
  "esac", "in", "!", "{", "}", "for", "select", "case",
]);

const WRAPPERS = new Set([
  "sudo", "env", "nice", "command", "builtin", "exec", "nohup", "time",
  "timeout", "stdbuf",
]);

const WRAPPER_OPTIONS_WITH_OPERANDS = new Set([
  "sudo:-u", "sudo:--user", "sudo:-g", "sudo:--group", "sudo:-h",
  "sudo:--host", "sudo:-p", "sudo:--prompt", "sudo:-C", "sudo:--chdir",
  "sudo:-R", "sudo:--role", "sudo:-T", "sudo:--command-timeout",
  "sudo:-D", "sudo:--chroot", "sudo:-U", "sudo:--other-user",
  "sudo:-t", "sudo:--type", "env:-u", "env:--unset", "env:-C",
  "env:--chdir", "nice:-n", "nice:--adjustment", "time:-o",
  "time:--output", "time:-f", "time:--format", "exec:-a",
  "exec:--argv0", "timeout:-s", "timeout:--signal", "timeout:-k",
  "timeout:--kill-after", "stdbuf:-i", "stdbuf:--input", "stdbuf:-o",
  "stdbuf:--output", "stdbuf:-e", "stdbuf:--error",
]);

const SHELLS = new Set(["sh", "bash", "dash", "zsh"]);

// Heredoc bodies feeding these commands (or a pipe to a shell on the opening
// line) are executed, so they are recursively analyzed as shell code. Every
// other heredoc body is data and never produces executable markers.
const HEREDOC_CODE_RECEIVERS = new Set(["sh", "bash", "dash", "zsh", "ksh", "ssh"]);

// Only documented global-option arities are skipped. An unknown option can
// hide the subcommand boundary, so it produces an unsupported-syntax marker.
const GLOBAL_VALUE_OPTIONS = {
  docker: new Set(["--config", "--context", "-c", "--host", "-H", "--log-level", "-l", "--tlscacert", "--tlscert", "--tlskey"]),
  kubectl: new Set(["--namespace", "-n", "--context", "--cluster", "--server", "-s", "--user", "--kubeconfig", "--token", "--username", "--password", "--client-certificate", "--client-key", "--certificate-authority", "--request-timeout", "--as", "--as-group", "--as-uid", "--cache-dir", "--v", "-v", "--vmodule", "--profile", "--profile-output", "--kuberc"]),
  aws: new Set(["--profile", "--region", "--output", "--endpoint-url", "--query", "--ca-bundle", "--cli-read-timeout", "--cli-connect-timeout", "--color", "--cli-binary-format"]),
};
const GLOBAL_FLAG_OPTIONS = {
  docker: new Set(["--debug", "-D", "--tls", "--tlsverify", "--version", "-v", "--help"]),
  kubectl: new Set(["--insecure-skip-tls-verify", "--disable-compression", "--match-server-version", "--warnings-as-errors", "--help"]),
  aws: new Set(["--debug", "--no-verify-ssl", "--no-paginate", "--no-sign-request", "--version", "--no-cli-pager", "--cli-auto-prompt", "--no-cli-auto-prompt", "--help"]),
};

function isNameStart(char) {
  return char !== undefined && /[A-Za-z_]/.test(char);
}

function isNameChar(char) {
  return char !== undefined && /[A-Za-z0-9_]/.test(char);
}

function stripAssignmentQuotes(value) {
  let output = value;
  if (output.startsWith('"')) output = output.slice(1);
  if (output.endsWith('"')) output = output.slice(0, -1);
  if (output.startsWith("'")) output = output.slice(1);
  if (output.endsWith("'")) output = output.slice(0, -1);
  return output;
}

/** Resolve MAINFRAME's deliberately small $VAR/${VAR} subset without a shell. */
export function resolveGateCommand(input, environment = process.env) {
  const assignments = new Map();
  let rest = String(input);
  const assignment = /^([A-Za-z_][A-Za-z0-9_]*)=([^\s;&|]*)[\s;&|]+/;

  while (true) {
    const match = rest.match(assignment);
    if (!match) break;
    assignments.set(match[1], stripAssignmentQuotes(match[2]));
    rest = rest.slice(match[0].length);
  }

  let output = "";
  for (let index = 0; index < rest.length; index += 1) {
    const char = rest[index];
    if (char !== "$") {
      output += char;
      continue;
    }

    let name = "";
    if (rest[index + 1] === "{") {
      let cursor = index + 2;
      if (isNameStart(rest[cursor])) {
        name += rest[cursor];
        cursor += 1;
        while (isNameChar(rest[cursor])) {
          name += rest[cursor];
          cursor += 1;
        }
      }
      if (!name || rest[cursor] !== "}") {
        output += char;
        continue;
      }
      index = cursor;
    } else if (isNameStart(rest[index + 1])) {
      let cursor = index + 1;
      while (isNameChar(rest[cursor])) {
        name += rest[cursor];
        cursor += 1;
      }
      index = cursor - 1;
    } else {
      output += char;
      continue;
    }

    if (assignments.has(name)) {
      output += assignments.get(name);
    } else if (Object.prototype.hasOwnProperty.call(environment, name) &&
               environment[name] !== undefined && environment[name] !== null) {
      output += String(environment[name]);
    }
  }
  return output;
}

function decodeCodePoint(value) {
  try {
    return String.fromCodePoint(value);
  } catch {
    return "";
  }
}

// Mirror the printf %b subset used by _agent_gate_decode_word. Unknown and
// incomplete escapes remain literal so they cannot silently become syntax.
function decodePercentB(input) {
  let output = "";
  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (char !== "\\" || index + 1 >= input.length) {
      output += char;
      continue;
    }

    const escape = input[index + 1];
    const simple = {
      a: "\x07", b: "\b", e: "\x1b", E: "\x1b", f: "\f", n: "\n",
      r: "\r", t: "\t", v: "\v", "\\": "\\", "'": "'", '"': '"',
    };
    if (Object.prototype.hasOwnProperty.call(simple, escape)) {
      output += simple[escape];
      index += 1;
      continue;
    }

    if (escape === "x") {
      const digits = input.slice(index + 2).match(/^[0-9A-Fa-f]{1,2}/)?.[0] || "";
      if (digits) {
        output += decodeCodePoint(Number.parseInt(digits, 16));
        index += 1 + digits.length;
      } else {
        output += "\\x";
        index += 1;
      }
      continue;
    }

    if (escape === "u" || escape === "U") {
      const maximum = escape === "u" ? 4 : 8;
      const pattern = new RegExp(`^[0-9A-Fa-f]{1,${maximum}}`);
      const digits = input.slice(index + 2).match(pattern)?.[0] || "";
      if (digits) {
        output += decodeCodePoint(Number.parseInt(digits, 16));
        index += 1 + digits.length;
      } else {
        output += `\\${escape}`;
        index += 1;
      }
      continue;
    }

    if (escape === "0") {
      const digits = input.slice(index + 2).match(/^[0-7]{0,3}/)?.[0] || "";
      output += decodeCodePoint(Number.parseInt(digits || "0", 8) & 0xff);
      index += 1 + digits.length;
      continue;
    }

    if (/[1-7]/.test(escape)) {
      const digits = input.slice(index + 1).match(/^[0-7]{1,3}/)?.[0] || escape;
      output += decodeCodePoint(Number.parseInt(digits, 8) & 0xff);
      index += digits.length;
      continue;
    }

    output += `\\${escape}`;
    index += 1;
  }
  return output;
}

/** Decode quote concatenation, escapes, and ANSI-C words without expansion. */
export function decodeGateWord(input) {
  let output = "";
  let quote = "";

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (quote === "'") {
      if (char === "'") quote = "";
      else output += char;
      continue;
    }
    if (quote === '"') {
      if (char === '"') {
        quote = "";
      } else if (char === "\\" && index + 1 < input.length) {
        const next = input[index + 1];
        if (["$", "`", '"', "\\"].includes(next)) {
          output += next;
          index += 1;
        } else if (next === "\n") {
          index += 1;
        } else {
          output += char;
        }
      } else {
        output += char;
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }
    if (char === "$" && input[index + 1] === "'") {
      let body = "";
      let escaped = false;
      let cursor = index + 2;
      for (; cursor < input.length; cursor += 1) {
        const ansiChar = input[cursor];
        if (ansiChar === "'" && !escaped) break;
        body += ansiChar;
        if (ansiChar === "\\" && !escaped) escaped = true;
        else escaped = false;
      }
      if (cursor < input.length) {
        if (body.includes("\\c")) output += `$'${body}'`;
        else output += decodePercentB(body);
        index = cursor;
      } else {
        output += char;
      }
      continue;
    }
    if (char === "\\") {
      if (index + 1 < input.length) {
        index += 1;
        if (input[index] !== "\n") output += input[index];
      } else {
        output += char;
      }
      continue;
    }
    output += char;
  }
  return output;
}

function tokenizeCommand(input) {
  const tokens = [];
  const heredocs = [];
  let pendingHeredoc = null;
  for (let index = 0; index < input.length;) {
    const char = input[index];
    if (char === " " || char === "\t") {
      tokens.push({ type: "space", value: char });
      index += 1;
      continue;
    }
    if (char === "#") {
      const end = input.indexOf("\n", index);
      tokens.push({ type: "comment", value: input.slice(index, end < 0 ? input.length : end) });
      index = end < 0 ? input.length : end;
      continue;
    }
    // Longest match keeps descriptor duplication/moves and combined-output
    // redirects intact; their '&' is not a command-list separator.
    const redirect = ["&>>", "<<<", "<<-", "&>", ">>", "<>", ">&", "<&", ">|", "<<", ">", "<"]
      .find((operator) => input.startsWith(operator, index));
    if (redirect) {
      if (redirect === "<<" || redirect === "<<-") {
        if (pendingHeredoc !== null) tokens.unsupported = true;
        pendingHeredoc = redirect === "<<-";
      }
      tokens.push({ type: "operator", value: redirect });
      index += redirect.length;
      continue;
    }
    if (["\n", ";", "|", "&", "(", ")"].includes(char)) {
      if (pendingHeredoc !== null) tokens.unsupported = true;
      tokens.push({ type: "separator", value: char });
      index += 1;
      // Consume queued bodies as physical lines BEFORE ordinary word quoting.
      // Quotes and shell-looking text inside a body cannot hide its delimiter.
      if (char === "\n") {
        for (const { delim, strip, quoted } of heredocs.splice(0)) {
          while (index < input.length) {
            const end = input.indexOf("\n", index);
            const line = input.slice(index, end < 0 ? input.length : end);
            const check = strip ? line.replace(/^\t+/, "") : line;
            const closed = check === delim;
            tokens.push({ type: closed ? "heredoc-end" : quoted ? "heredoc-inert" : "heredoc-expandable", value: line });
            // Unquoted backslash-newline changes delimiter recognition. Do not
            // guess where such a body ends in this deliberately bounded lexer.
            if (!quoted && /(?:^|[^\\])(?:\\\\)*\\$/.test(line)) tokens.unsupported = true;
            if (end >= 0) tokens.push({ type: "separator", value: "\n" });
            index = end < 0 ? input.length : end + 1;
            if (closed) break;
          }
        }
      }
      continue;
    }
    let word = "", quote = "", ansi = false;
    while (index < input.length) {
      const ch = input[index];
      if (!quote && /[ \t\n;<>&|()]/.test(ch)) break;
      word += ch;
      if (quote) {
        if (ch === quote) quote = "";
        else if (ch === "\\" && (quote === '"' || ansi) && index + 1 < input.length) word += input[++index];
      } else if (ch === "'" || ch === '"') {
        ansi = ch === "'" && input[index - 1] === "$";
        quote = ch;
      } else if (ch === "\\") {
        if (index + 1 < input.length) word += input[++index];
        else tokens.unsupported = true;
      }
      index += 1;
    }
    if (quote) tokens.unsupported = true;
    tokens.push({ type: "word", value: word });
    if (pendingHeredoc !== null) {
      const delim = decodeGateWord(word);
      const quoted = /["'\\]/.test(word);
      if (delim.includes("\n") || (!quoted && /[$`]/.test(delim))) tokens.unsupported = true;
      heredocs.push({ delim, strip: pendingHeredoc, quoted });
      pendingHeredoc = null;
    }
  }
  if (pendingHeredoc !== null) tokens.unsupported = true;
  return tokens;
}

function executableBasename(value) {
  return value.slice(value.lastIndexOf("/") + 1).toLowerCase();
}

/**
 * Normalize one already-resolved command string and mark executable words.
 * Call normalizeGateCommand for the public resolved-command contract.
 */
export function normalizeGateCommandPaths(input, depth = 0) {
  if (depth >= 20) return `${EXECUTABLE_MARKER}mainframe-unsupported-shell-syntax `;
  const tokens = tokenizeCommand(String(input));
  let output = tokens.unsupported ? `${EXECUTABLE_MARKER}mainframe-unsupported-shell-syntax ` : "";
  if (hasDynamicShellExpansion(input)) output += `${EXECUTABLE_MARKER}mainframe-dynamic-shell-expansion `;
  let atCommand = true;
  let wrapper = "";
  let wrapperArgPending = 0;
  let wrapperSplitStringPending = false;
  let wrapperTimeoutDuration = false;
  let currentCommand = "";
  let shellCodePending = false;
  let findExecPending = false;
  let findEmbeddedShell = false;
  let gitPreamble = false;
  let terraformPreamble = false;
  let globalPreamble = "";
  let gitReset = false, gitOptionsEnded = false;
  let optionArgPending = 0;
  let gitConfigArgPending = false;
  let redirectTargetPending = false;
  let hereStringPending = false;
  let functionNamePending = false;
  // Heredoc tracking: << / <<- queue a body that begins at the next newline.
  const heredocQueue = [];
  let heredocDelimPending = false;
  let heredocStripTabs = false;
  let bodyMode = false;
  let bodyCmd = "";
  let bodyTabs = false;
  let bodyDelim = "";
  let bodyCode = false;
  let bodyLine = "";
  let bodyText = "";
  let bodyLinePiped = false;
  let pendingPipe = false;
  let linePipesToShell = false;

  const resetAtBoundary = () => {
    atCommand = true;
    wrapper = "";
    wrapperArgPending = 0;
    wrapperSplitStringPending = false;
    wrapperTimeoutDuration = false;
    currentCommand = "";
    shellCodePending = false;
    findExecPending = false;
    findEmbeddedShell = false;
    gitPreamble = false;
    terraformPreamble = false;
    globalPreamble = "";
    gitReset = false; gitOptionsEnded = false;
    optionArgPending = 0;
    gitConfigArgPending = false;
    redirectTargetPending = false;
    hereStringPending = false;
    functionNamePending = false;
  };

  const popHeredoc = () => {
    const next = heredocQueue.shift();
    bodyCmd = next.cmd;
    bodyTabs = next.stripTabs;
    bodyDelim = next.delim;
    bodyCode = HEREDOC_CODE_RECEIVERS.has(next.cmd) || bodyLinePiped;
    bodyLine = "";
    bodyText = "";
  };

  for (let ti = 0; ti < tokens.length; ti += 1) {
    const token = tokens[ti];
    const raw = token.value;

    if (token.type === "comment") continue;

    // Heredoc body: accumulate lines until the closing delimiter. Body words
    // are data and never receive executable markers; a body feeding a shell
    // or interpreter is analyzed recursively as shell code.
    if (bodyMode) {
      if (token.type === "separator" && raw === "\n") {
        let line = bodyLine;
        if (bodyTabs) line = line.replace(/^\t+/, "");
        if (line === bodyDelim) {
          if (bodyCode && bodyText) output += ` ; ${normalizeGateCommandPaths(bodyText, depth + 1)}`;
          output += "\n";
          if (heredocQueue.length) {
            popHeredoc();
          } else {
            bodyMode = false;
            bodyLine = "";
            bodyText = "";
            // The delimiter line ended the body; the next line is a fresh
            // command position.
            resetAtBoundary();
          }
        } else {
          bodyText += `${bodyLine}\n`;
          bodyLine = "";
        }
        continue;
      }
      bodyLine += raw;
      continue;
    }

    if (token.type === "space") {
      output += raw;
      continue;
    }
    if (token.type === "separator") {
      output += raw;
      resetAtBoundary();
      heredocDelimPending = false;
      if (raw === "|") {
        pendingPipe = true;
      } else {
        pendingPipe = false;
      }
      if (raw === "\n") {
        if (heredocQueue.length) {
          bodyLinePiped = linePipesToShell;
          popHeredoc();
          bodyMode = true;
        }
        linePipesToShell = false;
      }
      continue;
    }
    if (token.type === "operator") {
      // Redirection syntax and operands are not command arguments. Omitting
      // them also prevents descriptor '&' from truncating later option scans.
      output += " ";
      if (raw === "<<<") {
        hereStringPending = true;
      } else if (raw === "<<" || raw === "<<-") {
        heredocDelimPending = true;
        heredocStripTabs = raw === "<<-";
      } else {
        redirectTargetPending = true;
      }
      continue;
    }

    const plain = decodeGateWord(raw);

    // Heredoc delimiter word: queue the body spec instead of treating the
    // word as an argument. "<<-" strips leading tabs from body lines.
    if (heredocDelimPending) {
      const spec = raw;
      const delim = decodeGateWord(spec);
      const quoted = /["'\\]/.test(spec);
      // Delimiters outside the bounded lexer fail closed.
      const valid = !delim.includes("\n") &&
        (quoted || !/[$`]/.test(delim));
      if (valid) {
        heredocQueue.push({ cmd: currentCommand, stripTabs: heredocStripTabs, delim });
        output += raw;
        heredocDelimPending = false;
        continue;
      }
      heredocDelimPending = false;
      output += `${EXECUTABLE_MARKER}mainframe-unsupported-shell-syntax `;
    }

    if (hereStringPending) {
      if (!currentCommand) output += `${EXECUTABLE_MARKER}mainframe-unsupported-shell-syntax `;
      else if (HEREDOC_CODE_RECEIVERS.has(currentCommand)) output += ` ; ${normalizeGateCommandPaths(plain, depth + 1)} ; `;
      else output += plain;
      hereStringPending = false;
      continue;
    }

    if (redirectTargetPending) {
      if (/^\/dev\/(?:sd|disk|rdisk|nvme)/i.test(plain)) {
        output += `${EXECUTABLE_MARKER}mainframe-raw-device-redirect `;
      }
      redirectTargetPending = false;
      continue;
    }

    if (/^[0-9]+$/.test(raw) && tokens[ti + 1]?.type === "operator") continue;

    if (wrapperSplitStringPending) {
      output += ` ${normalizeGateCommandPaths(plain, depth + 1)}`;
      wrapperSplitStringPending = false;
      continue;
    }
    if (shellCodePending) {
      output += ` ; ${normalizeGateCommandPaths(plain, depth + 1)}`;
      shellCodePending = false;
      continue;
    }
    if (findExecPending) {
      const command = executableBasename(plain);
      output += `${EXECUTABLE_MARKER}${command}`;
      findExecPending = false;
      findEmbeddedShell = SHELLS.has(command);
      continue;
    }

    if (atCommand) {
      if (functionNamePending) {
        output += plain;
        functionNamePending = false;
        atCommand = true;
        continue;
      }
      if (plain === "function") {
        output += raw;
        functionNamePending = true;
        atCommand = true;
        continue;
      }
      if (CONTROL_WORDS.has(plain)) {
        output += raw;
        atCommand = true;
        continue;
      }
      if (!wrapper && /^[A-Za-z_][A-Za-z0-9_]*=/.test(plain)) {
        output += raw;
        continue;
      }

      if (wrapper) {
        if (wrapperArgPending) {
          wrapperArgPending -= 1;
          continue;
        }
        if (wrapper === "timeout" && wrapperTimeoutDuration &&
            /^[0-9]+(?:[.][0-9]+)?[smhd]?$/.test(plain)) {
          wrapperTimeoutDuration = false;
          continue;
        }
        if (wrapper === "env" && /^[A-Za-z_][A-Za-z0-9_]*=/.test(plain)) {
          continue;
        }
        if (plain === "--") continue;
        if (plain.startsWith("-")) {
          if (wrapper === "env" &&
              (plain.startsWith("--split-string=") ||
               (plain.startsWith("-S") && plain !== "-S"))) {
            const inner = plain.startsWith("--split-string=")
              ? plain.slice(plain.indexOf("=") + 1)
              : plain.slice(2);
            output += ` ${normalizeGateCommandPaths(inner, depth + 1)}`;
            continue;
          }
          if (wrapper === "env" && (plain === "-S" || plain === "--split-string")) {
            wrapperSplitStringPending = true;
          } else if (WRAPPER_OPTIONS_WITH_OPERANDS.has(`${wrapper}:${plain}`)) {
            wrapperArgPending = 1;
          }
          continue;
        }
      }

      const command = executableBasename(plain);
      output += `${EXECUTABLE_MARKER}${command}`;
      currentCommand = command;
      atCommand = false;
      wrapper = "";
      gitPreamble = false;
      terraformPreamble = false;
      globalPreamble = "";
      optionArgPending = 0;
      if (WRAPPERS.has(command)) {
        wrapper = command;
        atCommand = true;
        currentCommand = "";
        if (command === "timeout") wrapperTimeoutDuration = true;
      } else if (command === "git") {
        gitPreamble = true;
      } else if (command === "terraform" || command === "tofu") {
        terraformPreamble = true;
      } else if (Object.prototype.hasOwnProperty.call(GLOBAL_VALUE_OPTIONS, command)) {
        globalPreamble = command;
      }
      if (!WRAPPERS.has(command)) {
        for (const pending of heredocQueue) if (!pending.cmd) pending.cmd = command;
      }
      // A non-wrapper command consumes a pending pipe; remember when a shell
      // receives it so a queued heredoc body stays shell code.
      if (wrapper !== command && pendingPipe) {
        if (SHELLS.has(command)) linePipesToShell = true;
        pendingPipe = false;
      }
      continue;
    }

    if (findEmbeddedShell && /^-[^-]*c[^-]*$/.test(plain)) {
      output += plain;
      shellCodePending = true;
      continue;
    }
    if (SHELLS.has(currentCommand) && /^-[^-]*c[^-]*$/.test(plain)) {
      output += plain;
      shellCodePending = true;
      continue;
    }

    if (gitPreamble) {
      if (optionArgPending) {
        optionArgPending -= 1;
        if (gitConfigArgPending && /^alias\..*=/.test(plain.toLowerCase())) {
          output += `${EXECUTABLE_MARKER}mainframe-inline-git-alias`;
        }
        gitConfigArgPending = false;
        continue;
      }
      if (plain === "-c" || plain === "--config-env") {
        optionArgPending = 1;
        gitConfigArgPending = true;
        continue;
      }
      if (["-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix"].includes(plain)) {
        optionArgPending = 1;
        gitConfigArgPending = false;
        continue;
      }
      if (/^-calias\..*=/i.test(plain)) {
        output += `${EXECUTABLE_MARKER}mainframe-inline-git-alias`;
        continue;
      }
      if (/^--config-env=alias\.[^=]+=/i.test(plain)) {
        output += `${EXECUTABLE_MARKER}mainframe-inline-git-alias`;
        continue;
      }
      if (/^(?:--git-dir|--work-tree|--namespace|--super-prefix|--config-env)=/.test(plain) ||
          plain.startsWith("-")) {
        continue;
      }
      gitPreamble = false;
      gitReset = plain.toLowerCase() === "reset";
    } else if (terraformPreamble) {
      if (optionArgPending) {
        optionArgPending -= 1;
        continue;
      }
      if (plain === "-chdir") {
        optionArgPending = 1;
        continue;
      }
      if (plain.startsWith("-chdir=") || plain.startsWith("-")) continue;
      terraformPreamble = false;
    } else if (globalPreamble) {
      if (optionArgPending) { optionArgPending -= 1; continue; }
      const values = GLOBAL_VALUE_OPTIONS[globalPreamble];
      const flags = GLOBAL_FLAG_OPTIONS[globalPreamble];
      const key = plain.split("=", 1)[0];
      if (values.has(plain)) { optionArgPending = 1; continue; }
      if ((plain.includes("=") && (values.has(key) || flags.has(key))) || flags.has(plain)) continue;
      if ((globalPreamble === "docker" && /^-[cHl].+/.test(plain)) ||
          (globalPreamble === "kubectl" && /^-[nsv].+/.test(plain))) continue;
      if (plain === "--") { globalPreamble = ""; continue; }
      if (plain.startsWith("-")) {
        output += `${EXECUTABLE_MARKER}mainframe-unsupported-shell-syntax `;
        continue;
      }
      globalPreamble = "";
    }

    if (currentCommand === "git" && gitReset) {
      if (plain === "--") gitOptionsEnded = true;
      if (plain === "--hard" && !gitOptionsEnded) output += `${EXECUTABLE_MARKER}mainframe-git-reset-hard `;
    }

    if (currentCommand === "find" && /^-exec(?:dir)?$/.test(plain)) {
      findExecPending = true;
    }
    output += plain;
  }

  // End of input closes a heredoc body whose final line has no newline (the
  // shell accepts EOF-terminated heredocs with a warning).
  if (bodyMode) {
    let line = bodyLine;
    if (bodyTabs) line = line.replace(/^\t+/, "");
    if (line !== bodyDelim) bodyText += bodyLine;
    if (bodyCode && bodyText) output += ` ; ${normalizeGateCommandPaths(bodyText, depth + 1)}`;
  }

  return output;
}

// Heredoc expansion uses double-quote-like backslash rules, but quote
// characters in the body are literal and cannot suppress $() or backticks.
function heredocHasExpansion(input) {
  for (let i = 0; i < input.length; i += 1) {
    if (input[i] === "\\" && /[$\x60\\\n]/.test(input[i + 1] || "")) { i += 1; continue; }
    if (input[i] === "\x60" || (input[i] === "$" && input[i + 1] === "(")) return true;
  }
  return false;
}

/** Analysis view: omit inert bodies/comments and expose active heredoc expansion. */
export function maskInertHeredocs(value) {
  return tokenizeCommand(String(value)).map((token) => {
    if (token.type === "heredoc-expandable") return heredocHasExpansion(token.value) ? " $(mainframe-heredoc-expansion) " : "";
    if (token.type.startsWith("heredoc-") || token.type === "comment") return "";
    return token.value;
  }).join("");
}

function hasDynamicShellExpansion(value) {
  const input = maskInertHeredocs(value);
  let quote = "", ansiQuote = false;
  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i], next = input[i + 1];
    if (quote === "'") {
      if (ch === "'") quote = "";
      else if (ch === "\\" && ansiQuote) i += 1;
      continue;
    }
    if (quote === '"') {
      if (ch === '"') quote = "";
      else if (ch === "\\" && /[$\x60"\\\n]/.test(next || "")) i += 1;
      else if (ch === "\x60" || (ch === "$" && next === "(")) return true;
      continue;
    }
    if (ch === "'" || ch === '"') { quote = ch; ansiQuote = ch === "'" && input[i - 1] === "$"; }
    else if (ch === "\\") i += 1;
    else if (ch === "\x60" || (ch === "$" && next === "(") || ((ch === "<" || ch === ">") && next === "(")) return true;
  }
  return false;
}

/** Resolve simple variables, then return the executable-marker command form. */
export function normalizeGateCommand(input, environment = process.env) {
  return normalizeGateCommandPaths(resolveGateCommand(String(input), environment));
}

/** Prepare every auditable input view used by exported gate rules. */
export function prepareGateCommand(input, environment = process.env) {
  const raw = String(input);
  const normalized = normalizeGateCommand(raw, environment);
  const rawNormalized = normalizeGateCommandPaths(raw);
  return {
    raw,
    rawInert: maskInertHeredocs(raw),
    normalized,
    rawNormalized,
    flat: normalized.split(EXECUTABLE_MARKER).join("").toLowerCase(),
  };
}

function inputsForRule(rule, prepared) {
  switch (rule.input) {
    case "raw": return [prepared.raw];
    case "raw-inert": return [prepared.rawInert];
    case "normalized-both": return [prepared.normalized, prepared.rawNormalized];
    case "flat": return [prepared.flat];
    case "normalized": return [prepared.normalized];
    default: throw new Error(`unsupported gate-rule input contract: ${rule.input}`);
  }
}

/** Apply exported regexes with their declared raw/normalized input contract. */
export function classifyGateCommand(input, rules, environment = process.env) {
  const prepared = prepareGateCommand(input, environment);
  for (const rule of rules) {
    const expression = new RegExp(rule.js, "i");
    if (inputsForRule(rule, prepared).some((value) => expression.test(value))) {
      return { tier: rule.tier, id: rule.id };
    }
  }
  return { tier: "low", id: "none" };
}
