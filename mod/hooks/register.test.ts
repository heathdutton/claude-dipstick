import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

type Answer = { exitCode: number; stdout: string; stderr?: string }
type Surface = 'terminal' | 'desktop' | 'vscode' | 'mobile'

const SCRIPT = '/fake/statusline.sh'
const HOME = '/fake-home'

function agent(id: string, rowIds: string[], tokenCount = 50000) {
  return {
    id, rowIds, name: id, type: 'general-purpose', description: `working on ${id}`, label: `working on ${id}`,
    status: 'running' as const, taskStatus: 'running' as const, kind: 'local_agent' as const, startTime: 0,
    cwd: '/tmp', model: 'claude-opus-5-5', effort: 'high' as const, contextWindowSize: 200000, tokenCount,
    tokenSamples: [tokenCount], hasRow: true, isHidden: false, columns: 100,
  }
}

// Answers as statusline.sh's subagent mode does, so each row's body names the task it came from.
function rowsFor(stdin: string): Answer {
  const ids = [...stdin.matchAll(/"id":"([^"]+)"/g)].map(match => match[1])
  return { exitCode: 0, stdout: ids.map(id => JSON.stringify({ id, content: `row ${id}` })).join('\n') + '\n' }
}

// Stands in for the host beneath the mod: which files exist, what each run of the script answers, and the body the
// mod hands the engine for each row.
function host(on: On, { env = {}, files = [SCRIPT], answer = rowsFor }: {
  env?: Record<string, string>
  files?: string[]
  answer?: (stdin: string) => Answer
} = {}) {
  const runs: { argv: readonly string[]; stdin: string }[] = []
  const bodies = new Map<string, string | undefined>()
  const logs: string[] = []
  on('env.get', (_, e) => ({ value: { CLAUDE_DIPSTICK_SCRIPT: SCRIPT, ...env }[e.name] || undefined }))
  on('fs.exists', (_, e) => ({ value: files.includes(e.path) }))
  on('process.run', (_, e) => {
    const stdin = e.init?.stdin ?? ''
    runs.push({ argv: e.argv, stdin })
    const { exitCode, stdout, stderr = '' } = answer(stdin)
    return { value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.log', (_, e) => {
    logs.push(e.text)
    return { value: undefined }
  })
  on('ui.render', { component: 'AgentRow' }, (_, e, next) => {
    bodies.set(e.props.id, e.props.body)
    return next(e)
  })
  return { runs, bodies, logs }
}

function mount($: Engine, surface: Surface, id: string, rowIds: string[]) {
  return $.ui.mount({ plugin: 'dipstick', surface, component: 'AgentRow', props: agent(id, rowIds) })
}

test('one run of the script draws every row asked in a pass', async ($, on) => {
  const { runs, bodies } = host(on)
  const ids = ['a1', 'a2']
  const rows = await Promise.all(ids.map(id => mount($, 'terminal', id, ids)))

  expect(bodies.get('a1')).toBe('row a1')
  expect(bodies.get('a2')).toBe('row a2')
  expect(runs).toHaveLength(1)
  expect(runs[0]?.argv).toEqual(['bash', SCRIPT])
  expect(JSON.parse(runs[0]?.stdin ?? '')).toMatchObject({
    hook_event_name: 'SubagentStatus',
    columns: 100,
    tasks: [{ id: 'a1', name: 'a1', model: 'claude-opus-5-5', effort: 'high', contextWindowSize: 200000 },
      { id: 'a2' }],
  })
  for (const row of rows) await row.unmount()
})

test('the script the status line runs comes first', async ($, on) => {
  const ownScript = `${HOME}/.claude/statusline.sh`
  const { runs, bodies } = host(on, { env: { CLAUDE_DIPSTICK_SCRIPT: '', HOME }, files: [ownScript] })
  const row = await mount($, 'terminal', 'a1', ['a1'])
  expect(runs[0]?.argv).toEqual(['bash', ownScript])
  expect(bodies.get('a1')).toBe('row a1')
  await row.unmount()
})

test('a script named in CLAUDE_DIPSTICK_SCRIPT is never passed over for another', async ($, on) => {
  const { runs, bodies } = host(on, {
    env: { CLAUDE_DIPSTICK_SCRIPT: '/missing.sh', HOME },
    files: [`${HOME}/.claude/statusline.sh`],
  })
  const row = await mount($, 'terminal', 'a1', ['a1'])
  expect(bodies.get('a1')).toBeUndefined()
  expect(runs).toHaveLength(0)
  await row.unmount()
})

test('desktop, VS Code and mobile keep the engine row', async ($, on) => {
  const { runs, bodies } = host(on)
  for (const surface of ['desktop', 'vscode', 'mobile'] as const) {
    const row = await mount($, surface, 'a1', ['a1'])
    expect(bodies.get('a1')).toBeUndefined()
    await row.unmount()
  }
  expect(runs).toHaveLength(0)
})

test('with no script anywhere the engine row stays and nothing runs', async ($, on) => {
  const { runs, bodies } = host(on, { env: { CLAUDE_DIPSTICK_SCRIPT: '', HOME }, files: [] })
  const row = await mount($, 'terminal', 'a1', ['a1'])
  expect(bodies.get('a1')).toBeUndefined()
  expect(runs).toHaveLength(0)
  await row.unmount()
})

test('a failing script keeps the engine row, is tried again, and is reported once', async ($, on) => {
  const { runs, bodies, logs } = host(on, { answer: () => ({ exitCode: 2, stdout: '', stderr: 'boom\nmore' }) })
  const row = await mount($, 'terminal', 'a1', ['a1'])
  expect(bodies.get('a1')).toBeUndefined()

  await row.redraw(agent('a1', ['a1']))
  expect(runs).toHaveLength(2)
  expect(logs).toHaveLength(1)
  expect(logs[0]).toContain('exited 2: boom')
  await row.unmount()
})

test('a row the script leaves out, or answers with a bad line, keeps the engine row', async ($, on) => {
  const { bodies } = host(on, { answer: () => ({ exitCode: 0, stdout: 'not json\n{"id":"a1","content":"row a1"}\n' }) })
  const ids = ['a1', 'a2']
  const rows = await Promise.all(ids.map(id => mount($, 'terminal', id, ids)))
  expect(bodies.get('a1')).toBe('row a1')
  expect(bodies.get('a2')).toBeUndefined()
  for (const row of rows) await row.unmount()
})
