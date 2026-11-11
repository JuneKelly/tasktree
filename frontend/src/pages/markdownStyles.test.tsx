import { screen } from '@testing-library/react'
import { beforeEach, expect, test } from 'vitest'
import css from '../index.css?raw'
import { mockApi } from '../test/mockApi'
import { schema, treeNode } from '../test/fixtures'
import { renderApp } from '../test/render'

// Guards against outline/page rules leaking into rendered notes (e.g. bullets disappearing).
// jsdom's computed-style cascade is unreliable for descendant selectors, so this checks the
// real stylesheet's rules with element.matches() instead.

let sheet: CSSStyleSheet
beforeEach(() => {
  const style = document.createElement('style')
  style.textContent = css
  document.head.appendChild(style)
  sheet = style.sheet!
  return () => style.remove()
})

const rules = () =>
  [...sheet.cssRules].flatMap((r) =>
    r instanceof CSSMediaRule ? [...r.cssRules] : [r],
  ).filter((r): r is CSSStyleRule => r instanceof CSSStyleRule)

const matching = (el: Element, prop: string) =>
  rules().filter((r) => r.style.getPropertyValue(prop) !== '' && el.matches(r.selectorText))

async function renderNotes() {
  mockApi({
    'GET /api/me': { body: { actor: 'human:june' } },
    'GET /api/schema': { body: schema },
    'GET /api/tree': {
      body: {
        data: [
          treeNode({ id: 'p', title: 'P', body: '## Sub\n\n- one\n  - nested\n\n1. first' }, [
            treeNode({ id: 'c', parent_id: 'p', title: 'C' }),
          ]),
        ],
      },
    },
  })
  renderApp('/')
  return screen.findByLabelText('Notes for P')
}

test('only markdown rules style lists inside notes; outline list rules stay on the outline', async () => {
  const notes = await renderNotes()
  for (const list of notes.querySelectorAll('ul, ol')) {
    const selectors = [...matching(list, 'list-style'), ...matching(list, 'list-style-type')].map((r) => r.selectorText)
    expect(selectors.length).toBeGreaterThan(0)
    for (const s of selectors) expect(s).toMatch(/^\.md /)
  }

  const outlineChildren = screen.getByDisplayValue('C').closest('ul')!
  expect(matching(outlineChildren, 'list-style').map((r) => r.selectorText)).toContain(
    '.outline, .outline ul.children',
  )
})

test('headings inside notes get their size from markdown rules, which outrank page heading rules', async () => {
  const notes = await renderNotes()
  const h2 = notes.querySelector('h2')!
  const sizes = matching(h2, 'font-size').map((r) => r.selectorText)
  expect(sizes).toEqual(expect.arrayContaining(['main h2', '.md h2']))
  // .md h2 (0,1,1) beats main h2 (0,0,2) on specificity.
})
