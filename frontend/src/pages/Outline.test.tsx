import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, test } from 'vitest'
import type { Editor } from '@tiptap/react'
import type { TreeNode } from '../api/types'
import { apiError, mockApi, type Mock } from '../test/mockApi'
import { node, schema, treeNode } from '../test/fixtures'
import { renderApp } from '../test/render'

const base = {
  'GET /api/me': { body: { actor: 'human:june' } },
  'GET /api/schema': { body: schema },
}

const withTree = (data: TreeNode[]) => ({ ...base, 'GET /api/tree': { body: { data } } })

function until<T>(fn: () => T | undefined, timeout = 1000): Promise<T> {
  return waitFor(
    () => {
      const v = fn()
      if (v === undefined) throw new Error('not yet')
      return v
    },
    { timeout },
  )
}

const one = (m: Mock, method: string, path: string, n = 1) =>
  until(() => (m.of(method, path).length >= n ? m.of(method, path)[n - 1] : undefined))

const blurAll = () => act(() => (document.activeElement as HTMLElement | null)?.blur())

describe('display', () => {
  test('rows show badge, editable title, tags, claim, blocked icon and rendered notes; collapse works', async () => {
    mockApi(
      withTree([
        treeNode({ id: 'p', title: 'Parent', tags: ['home'], body: 'Some **bold** notes' }, [
          treeNode({ id: 'c', parent_id: 'p', title: 'Child', blocked: true, claimed_by: 'agent:x', claim_expires_at: '2030-01-01T00:00:00Z' }),
        ]),
      ]),
    )
    renderApp('/')
    expect(await screen.findByDisplayValue('Parent')).toBeInTheDocument()
    expect(screen.getByText('#home')).toBeInTheDocument()
    expect(within(screen.getByLabelText('Notes for Parent')).getByText('bold').tagName).toBe('STRONG')
    expect(screen.getByText(/agent:x/)).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'blocked' })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Collapse Parent' }))
    expect(screen.queryByDisplayValue('Child')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Expand Parent' }))
    expect(screen.getByDisplayValue('Child')).toBeInTheDocument()
  })

  test('badge colour kind comes from the schema, not the state name', async () => {
    mockApi(
      withTree(
        ['TODO', 'DOING', 'DONE', 'MYSTERY'].map((state, i) => treeNode({ id: `n${i}`, title: `T${i}`, state })),
      ),
    )
    renderApp('/')
    await screen.findByDisplayValue('T0')
    const kinds = Object.fromEntries(
      ['TODO', 'DOING', 'DONE', 'MYSTERY'].map((s) => [s, screen.getByText(s, { selector: '.badge' }).dataset.kind]),
    )
    expect(kinds).toEqual({ TODO: 'actionable', DOING: 'active', DONE: 'terminal', MYSTERY: 'unknown' })
  })

  test('the state menu offers exactly the API-provided allowed transitions', async () => {
    mockApi(withTree([treeNode({ allowed_transitions: ['DOING', 'NEXT'] })]))
    renderApp('/')
    const menu = await screen.findByRole('combobox', { name: 'Change state of Write docs' })
    expect(within(menu).getAllByRole('option').map((o) => o.textContent)).toEqual(['→ state…', 'DOING', 'NEXT'])
  })
})

describe('transitions', () => {
  test('posts the node version in If-Match', async () => {
    const m = mockApi({
      ...withTree([treeNode({ version: 4 })]),
      'POST /api/nodes/n1/transition': { body: node({ state: 'DOING', version: 5 }) },
    })
    renderApp('/')
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'DOING')
    const req = await one(m, 'POST', '/api/nodes/n1/transition')
    expect(req.headers.get('if-match')).toBe('4')
    expect(req.body).toEqual({ to: 'DOING' })
  })

  test('a state that requires fields asks for them, from the schema', async () => {
    const m = mockApi({
      ...withTree([treeNode({ state: 'DOING', allowed_transitions: ['DONE'] })]),
      'POST /api/nodes/n1/transition': { body: node({ state: 'DONE' }) },
    })
    renderApp('/')
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'DONE')
    expect(m.of('POST', '/api/nodes/n1/transition')).toHaveLength(0)
    await userEvent.type(await screen.findByLabelText('outcome'), 'shipped')
    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))
    expect((await one(m, 'POST', '/api/nodes/n1/transition')).body).toEqual({ to: 'DONE', fields: { outcome: 'shipped' } })
  })

  test('a version conflict refetches and tells the user; nothing is retried', async () => {
    const m = mockApi({
      ...withTree([treeNode()]),
      'POST /api/nodes/n1/transition': apiError(409, 'version_conflict', { current: node({ version: 2 }) }),
    })
    renderApp('/')
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'NEXT')
    expect(await screen.findByRole('alert')).toHaveTextContent(/changed.*review and retry/i)
    await until(() => (m.of('GET', '/api/tree').length > 1 ? true : undefined))
    expect(m.of('POST', '/api/nodes/n1/transition')).toHaveLength(1)
  })
})

describe('inline title editing and autosave', () => {
  test('saving on blur chains versions: each save uses the previous response version', async () => {
    let v = 1
    const m = mockApi({
      ...withTree([treeNode({ version: 1 })]),
      'PATCH /api/nodes/n1': (req) => {
        v += 1
        return { body: node({ ...(req.body as object), version: v }) }
      },
    })
    renderApp('/')
    const title = await screen.findByDisplayValue('Write docs')
    await userEvent.type(title, '!')
    await blurAll()
    const first = await one(m, 'PATCH', '/api/nodes/n1')
    expect(first.headers.get('if-match')).toBe('1')
    expect(first.body).toEqual({ title: 'Write docs!' })

    await userEvent.type(title, '?')
    await blurAll()
    const second = await one(m, 'PATCH', '/api/nodes/n1', 2)
    expect(second.headers.get('if-match')).toBe('2')
    expect(second.body).toEqual({ title: 'Write docs!?' })
  })

  test('saves after a pause in typing, without leaving the field', async () => {
    const m = mockApi({ ...withTree([treeNode()]), 'PATCH /api/nodes/n1': { body: node({ version: 2 }) } })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('Write docs'), 'x')
    expect(screen.getByDisplayValue('Write docsx')).toHaveFocus()
    expect((await until(() => m.of('PATCH', '/api/nodes/n1')[0], 3000)).body).toEqual({ title: 'Write docsx' })
  })

  test('an emptied title is restored on blur and never sent', async () => {
    const m = mockApi(withTree([treeNode()]))
    renderApp('/')
    await userEvent.clear(await screen.findByDisplayValue('Write docs'))
    await blurAll()
    expect(await screen.findByDisplayValue('Write docs')).toBeInTheDocument()
    expect(m.of('PATCH', '/api/nodes/n1')).toHaveLength(0)
  })

  test('polling never replaces a field being edited; a stale save conflicts and Keep mine re-saves on top', async () => {
    let tree = [treeNode({ version: 1, title: 'Write docs' })]
    let patches = 0
    const m = mockApi({
      ...base,
      'GET /api/tree': () => ({ body: { data: tree } }),
      'PATCH /api/nodes/n1': (req) => {
        patches += 1
        return patches === 1
          ? apiError(409, 'version_conflict', { current: node({ version: 2, title: 'Their title' }) })
          : { body: node({ ...(req.body as object), version: 3 }) }
      },
    })
    const { client } = renderApp('/')
    const title = await screen.findByDisplayValue('Write docs')
    await userEvent.click(title)
    await userEvent.type(title, ' mine')

    // Someone else changes the title; the poll brings it in while we're typing.
    tree = [treeNode({ version: 2, title: 'Their title' })]
    await act(() => client.invalidateQueries({ queryKey: ['tree'] }))
    expect(screen.getByDisplayValue('Write docs mine')).toBeInTheDocument()

    await blurAll()
    const stale = await one(m, 'PATCH', '/api/nodes/n1')
    expect(stale.headers.get('if-match')).toBe('1')
    const conflict = await screen.findByRole('group', { name: /Conflict on/ })
    expect(conflict).toHaveTextContent('Their title')
    expect(screen.getByDisplayValue('Write docs mine')).toBeInTheDocument()

    await userEvent.click(within(conflict).getByRole('button', { name: 'Keep mine' }))
    const resave = await one(m, 'PATCH', '/api/nodes/n1', 2)
    expect(resave.headers.get('if-match')).toBe('2')
    expect(resave.body).toEqual({ title: 'Write docs mine' })
    await waitFor(() => expect(screen.queryByRole('group', { name: /Conflict on/ })).not.toBeInTheDocument())
  })

  test('Take theirs drops local edits and adopts the winning version', async () => {
    const m = mockApi({
      ...withTree([treeNode({ version: 1 })]),
      'PATCH /api/nodes/n1': apiError(409, 'version_conflict', { current: node({ version: 2, title: 'Their title' }) }),
    })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('Write docs'), ' mine')
    await blurAll()
    await userEvent.click(within(await screen.findByRole('group', { name: /Conflict on/ })).getByRole('button', { name: 'Take theirs' }))
    expect(await screen.findByDisplayValue('Their title')).toBeInTheDocument()
    expect(m.of('PATCH', '/api/nodes/n1')).toHaveLength(1)
  })

  test('a node claimed by someone else is read-only; your own claim is editable', async () => {
    mockApi(
      withTree([
        treeNode({ id: 'a', title: 'Theirs', body: 'notes', claimed_by: 'agent:x', claim_expires_at: '2030-01-01T00:00:00Z' }),
        treeNode({ id: 'b', title: 'Mine', claimed_by: 'human:june', claim_expires_at: '2030-01-01T00:00:00Z' }),
      ]),
    )
    renderApp('/')
    await waitFor(() => expect(screen.getByDisplayValue('Theirs')).toHaveAttribute('readonly'))
    expect(screen.getByDisplayValue('Mine')).not.toHaveAttribute('readonly')
    await userEvent.click(screen.getByLabelText('Notes for Theirs'))
    expect(screen.queryByRole('textbox', { name: 'Notes for Theirs' })).not.toBeInTheDocument()
  })
})

describe('notes', () => {
  test('clicking simple notes opens the rich editor', async () => {
    mockApi(withTree([treeNode({ body: 'Hello **world**' })]))
    renderApp('/')
    await userEvent.click(within(await screen.findByLabelText('Notes for Write docs')).getByText('world'))
    const editor = await screen.findByRole('textbox', { name: 'Notes for Write docs' })
    expect(editor).toHaveAttribute('contenteditable', 'true')
    expect(within(editor).getByText('world').tagName).toBe('STRONG')
  })

  test('a real rich-text edit saves the new markdown on blur', async () => {
    const m = mockApi({ ...withTree([treeNode({ body: 'Hello' })]), 'PATCH /api/nodes/n1': { body: node({ version: 2 }) } })
    renderApp('/')
    await userEvent.click(within(await screen.findByLabelText('Notes for Write docs')).getByText('Hello'))
    const el = await screen.findByRole('textbox', { name: 'Notes for Write docs' })
    await waitFor(() => expect(el).toHaveFocus())
    // jsdom can't type into ProseMirror; drive TipTap's own command (TipTap exposes it on the DOM node).
    const editor = (el as HTMLElement & { editor: Editor }).editor
    act(() => {
      editor.chain().focus('end').insertContent([{ type: 'text', text: ' ' }, { type: 'text', text: 'there', marks: [{ type: 'bold' }] }]).run()
    })
    await blurAll()
    expect((await one(m, 'PATCH', '/api/nodes/n1')).body).toEqual({ body: 'Hello **there**' })
  })

  test('notes the rich editor would change open as raw markdown; edits save on blur', async () => {
    const checklist = '- [ ] buy milk'
    const m = mockApi({ ...withTree([treeNode({ body: checklist })]), 'PATCH /api/nodes/n1': { body: node({ version: 2 }) } })
    renderApp('/')
    await userEvent.click(await screen.findByLabelText('Notes for Write docs'))
    const raw = await screen.findByRole('textbox', { name: 'Notes for Write docs' })
    expect(raw.tagName).toBe('TEXTAREA')
    expect(screen.getByText(/Editing as markdown/)).toBeInTheDocument()
    await userEvent.type(raw, '\nmore')
    await blurAll()
    expect((await one(m, 'PATCH', '/api/nodes/n1')).body).toEqual({ body: `${checklist}\nmore` })
  })

  test('tables render in notes and edit in the rich editor; saved markdown has no stray blank lines', async () => {
    const table = '| a | b |\n|---|---|\n| 1 | 2 |'
    const m = mockApi({ ...withTree([treeNode({ body: table })]), 'PATCH /api/nodes/n1': { body: node({ version: 2 }) } })
    renderApp('/')
    const view = await screen.findByLabelText('Notes for Write docs')
    expect(within(view).getByRole('table')).toBeInTheDocument()
    expect(within(view).getByRole('columnheader', { name: 'a' })).toBeInTheDocument()

    await userEvent.click(within(view).getByRole('cell', { name: '2' }))
    const el = await screen.findByRole('textbox', { name: 'Notes for Write docs' })
    expect(el).toHaveAttribute('contenteditable', 'true')
    expect(within(el).getByRole('table')).toBeInTheDocument()
    await waitFor(() => expect(el).toHaveFocus())
    const editor = (el as HTMLElement & { editor: Editor }).editor
    // Type at the end of the "2" cell.
    let afterTwo = -1
    editor.state.doc.descendants((n, pos) => {
      if (n.isText && n.text === '2') afterTwo = pos + 1
    })
    act(() => {
      editor.chain().focus().setTextSelection(afterTwo).insertContent('0').run()
    })
    await blurAll()
    const body = ((await one(m, 'PATCH', '/api/nodes/n1')).body as { body: string }).body
    expect(body).toMatch(/^\| a +\| b +\|\n/)
    expect(body).toMatch(/\| 1 +\| 20 +\|$/)
    expect(body).not.toMatch(/^\n|\n$/)
  })

  test('opening and closing notes without changes saves nothing', async () => {
    const m = mockApi(withTree([treeNode({ body: '* star bullets' })]))
    renderApp('/')
    await userEvent.click(within(await screen.findByLabelText('Notes for Write docs')).getByText('star bullets'))
    const editor = await screen.findByRole('textbox', { name: 'Notes for Write docs' })
    await waitFor(() => expect(editor).toHaveFocus())
    await blurAll()
    await waitFor(() => expect(screen.queryByRole('textbox', { name: 'Notes for Write docs' })).not.toBeInTheDocument())
    expect(m.of('PATCH', '/api/nodes/n1')).toHaveLength(0)
  })
})

describe('keyboard structure editing', () => {
  const kids = () => [
    treeNode({ id: 'p', title: 'P', version: 3 }, [
      treeNode({ id: 'a', parent_id: 'p', title: 'A', version: 5 }),
      treeNode({ id: 'b', parent_id: 'p', title: 'B', version: 7 }),
    ]),
    treeNode({ id: 'q', title: 'Q' }),
  ]

  test('Enter opens a new sibling below; typing and Enter creates it and continues', async () => {
    let n = 0
    const m = mockApi({ ...withTree(kids()), 'POST /api/nodes': () => ({ status: 201, body: node({ id: `new${++n}` }) }) })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('A'), '{Enter}')
    const draft = screen.getByRole('textbox', { name: 'New node title' })
    expect(draft).toHaveFocus()
    await userEvent.type(draft, 'Between{Enter}')
    expect((await one(m, 'POST', '/api/nodes')).body).toEqual({ title: 'Between', parent_id: 'p', after_id: 'a' })
  })

  test('Escape or an empty blur discards the new row', async () => {
    const m = mockApi(withTree(kids()))
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('A'), '{Enter}')
    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('textbox', { name: 'New node title' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '+ New node' }))
    await blurAll()
    expect(screen.queryByRole('textbox', { name: 'New node title' })).not.toBeInTheDocument()
    expect(m.of('POST', '/api/nodes')).toHaveLength(0)
  })

  test('"+ child" adds after the last child', async () => {
    const m = mockApi({ ...withTree(kids()), 'POST /api/nodes': { status: 201, body: node() } })
    renderApp('/')
    await screen.findByDisplayValue('P')
    await userEvent.click(screen.getAllByRole('button', { name: '+ child' })[0])
    await userEvent.type(screen.getByRole('textbox', { name: 'New node title' }), 'Last{Enter}')
    expect((await one(m, 'POST', '/api/nodes')).body).toEqual({ title: 'Last', parent_id: 'p', after_id: 'b' })
  })

  test('Tab indents under the previous sibling with If-Match; Tab on a first child does nothing', async () => {
    const m = mockApi({ ...withTree(kids()), 'POST /api/nodes/b/move': { body: node({ id: 'b', version: 8 }) } })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('A'), '{Tab}')
    await userEvent.type(screen.getByDisplayValue('B'), '{Tab}')
    const req = await one(m, 'POST', '/api/nodes/b/move')
    expect(req.body).toEqual({ parent_id: 'a' })
    expect(req.headers.get('if-match')).toBe('7')
    expect(m.calls.filter((c) => c.path.endsWith('/move'))).toHaveLength(1)
  })

  test('Shift+Tab outdents to just after the parent', async () => {
    const m = mockApi({ ...withTree(kids()), 'POST /api/nodes/a/move': { body: node({ id: 'a', version: 6 }) } })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('A'), '{Shift>}{Tab}{/Shift}')
    const req = await one(m, 'POST', '/api/nodes/a/move')
    expect(req.body).toEqual({ parent_id: null, after_id: 'p' })
    expect(req.headers.get('if-match')).toBe('5')
  })

  test('a failed move (cycle, conflict) is reported, not swallowed', async () => {
    mockApi({ ...withTree(kids()), 'POST /api/nodes/b/move': apiError(422, 'cycle') })
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('B'), '{Tab}')
    expect(await screen.findByRole('alert')).toHaveTextContent('cycle')
  })

  test('arrow keys move between visible titles, skipping collapsed children', async () => {
    mockApi(withTree(kids()))
    renderApp('/')
    await userEvent.click(await screen.findByDisplayValue('P'))
    await userEvent.keyboard('{ArrowDown}')
    expect(screen.getByDisplayValue('A')).toHaveFocus()
    await userEvent.keyboard('{ArrowUp}')
    expect(screen.getByDisplayValue('P')).toHaveFocus()

    await userEvent.click(screen.getByRole('button', { name: 'Collapse P' }))
    await userEvent.click(screen.getByDisplayValue('P'))
    await userEvent.keyboard('{ArrowDown}')
    expect(screen.getByDisplayValue('Q')).toHaveFocus()
  })

  test('Ctrl+ArrowDown opens the notes editor', async () => {
    mockApi(withTree(kids()))
    renderApp('/')
    await userEvent.type(await screen.findByDisplayValue('Q'), '{Control>}{ArrowDown}{/Control}')
    expect(await screen.findByRole('textbox', { name: 'Notes for Q' })).toBeInTheDocument()
  })
})
