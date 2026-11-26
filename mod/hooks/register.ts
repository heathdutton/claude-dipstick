// Draws each row of Claude Code's agent panel with statusline.sh, the script behind the status line. Its subagent
// mode reads the JSON subagentStatusLine sent and answers one {"id","content"} line per agent. This builds that
// payload and hands each line back as its row's body.
import type { EngineInterface, Register, RenderPropsOf } from 'claude-code'

type AgentRow = RenderPropsOf['AgentRow']
type Task = ReturnType<typeof task>
type Rows = ReadonlyMap<string, string>
type Reported = { failing: boolean }

const NO_ROWS: Rows = new Map()
// The engine kills a run when the ask that started it is abandoned, as when a row is asked again mid-run because its
// label or token count moved. Not the script's doing, so it's never reported, and a row still waiting runs it again.
const CUT: Rows = new Map()
// A hung script costs a plain row for this long, never a stuck panel.
const RUN_TIMEOUT_MS = 5000

export const register: Register = on => {
  // The engine asks once per row, every few seconds and on any change. One run draws them all from each row's
  // latest props.
  const seen = new Map<string, Task>()
  const reported: Reported = { failing: false }
  let lastPayload = ''
  let lastRun: Promise<Rows> = Promise.resolve(NO_ROWS)

  on('ui.render', { component: 'AgentRow' }, async ($, e, next) => {
    // Only the terminal is set up with a Nerd Font. The model marks would draw as boxes anywhere else.
    if (e.surface !== 'terminal') return next(e)

    const row = e.props
    // Recorded before the first await. Every row asked in one pass then makes the payload, whichever resumes first.
    seen.set(row.id, task(row))
    for (const id of seen.keys()) if (!row.rowIds.includes(id)) seen.delete(id)

    const script = await findScript($)
    if (script === undefined) return next(e)

    const tasks = row.rowIds.flatMap(id => seen.get(id) ?? [])
    const payload = JSON.stringify({ hook_event_name: 'SubagentStatus', columns: row.columns ?? 80, tasks })
    const start = () => {
      lastPayload = payload
      lastRun = run($, script, payload, next.signal, reported).then(rows => {
        // Retried at the next ask. Otherwise a failure stands until something on the panel changes.
        if ((rows === NO_ROWS || rows === CUT) && lastPayload === payload) lastPayload = ''
        return rows
      })
      return lastRun
    }
    const shared = payload === lastPayload ? lastRun : start()
    let rows = await shared
    // Only the first row back from a cut run starts another. The rest wait on that one.
    if (rows === CUT && !next.signal.aborted) rows = await (lastRun === shared ? start() : lastRun)

    const body = rows.get(row.id)
    return body === undefined ? next(e) : next({ ...e, props: { ...row, body } })
  })
}

// The fields subagentStatusLine sent, in its order. The script starts a task at its "id".
function task(row: AgentRow) {
  const { id, name, type, status, description, label, startTime, model, effort, contextWindowSize, tokenCount,
    tokenSamples, cwd } = row
  return { id, name, type, status, description, label, startTime, model, effort, contextWindowSize, tokenCount,
    tokenSamples, cwd }
}

// The script statusLine runs comes first, so rows match the line's version and config. CLAUDE_DIPSTICK_SCRIPT names
// another. A checkout keeps its own one folder up.
async function findScript($: EngineInterface): Promise<string | undefined> {
  const chosen = await $.env.get('CLAUDE_DIPSTICK_SCRIPT')
  if (chosen) return (await $.fs.exists(chosen)) ? chosen : undefined

  const home = await $.env.get('HOME')
  const candidates = [home ? `${home}/.claude/statusline.sh` : '', `${$.plugin.root}/../statusline.sh`]
  for (const path of candidates) {
    if (path && (await $.fs.exists(path))) return path
  }
  return undefined
}

async function run($: EngineInterface, script: string, payload: string, signal: AbortSignal,
  reported: Reported): Promise<Rows> {
  let failure: string
  try {
    const result = await $.process.run(['bash', script], { stdin: payload, timeoutMs: RUN_TIMEOUT_MS })
    if (result.exitCode === 0) {
      reported.failing = false
      return parseRows(result.stdout)
    }
    failure = `exited ${result.exitCode}: ${firstLine(result.stderr)}`
  } catch (error) {
    if (signal.aborted) return CUT
    failure = error instanceof Error ? error.message : String(error)
  }
  // Said once per failing stretch. The engine asks every few seconds, and each ask would say it again.
  // The engine leads every log line with the plugin's name, and its own errors too.
  if (!reported.failing) {
    reported.failing = true
    const said = failure.startsWith(`${$.plugin.name}: `) ? failure.slice($.plugin.name.length + 2) : failure
    $.ui.log(`${script} ${said}. Agent rows fall back to Claude Code's own until it runs clean.`)
  }
  return NO_ROWS
}

function parseRows(stdout: string): Rows {
  const rows = new Map<string, string>()
  for (const line of stdout.split('\n')) {
    if (!line.trim()) continue
    try {
      const row: unknown = JSON.parse(line)
      if (isRow(row)) rows.set(row.id, row.content)
    } catch {
      // A line that isn't JSON leaves its agent on the engine's row, as subagentStatusLine did.
    }
  }
  return rows
}

function isRow(value: unknown): value is { id: string; content: string } {
  if (typeof value !== 'object' || value === null) return false
  const { id, content } = value as { id?: unknown; content?: unknown }
  return typeof id === 'string' && typeof content === 'string'
}

function firstLine(text: string): string {
  return text.trim().split('\n')[0]?.slice(0, 200) || 'no output'
}
