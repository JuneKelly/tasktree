import { describe, expect, test } from 'vitest'
import { richEditable, roundTrip } from './markdown'

describe('markdown round trip through the rich editor', () => {
  test.each([
    'Plain paragraph.',
    'Two\n\nparagraphs.',
    '- a\n- b\n  - nested',
    '1. one\n2. two',
    '**bold**, *italic*, `code`',
    '# Heading\n\nText',
    '```\ncode block\n```',
    '> quote',
    '[link](https://example.com)',
  ])('lossless: %j', (md) => {
    expect(roundTrip(md)).toBe(md)
    expect(richEditable(md)).toBe(true)
  })

  test.each(['* star bullets\n* two', '_underscore italic_'])('cosmetic rewrite still allowed: %j', (md) => {
    expect(roundTrip(md)).not.toBe(md)
    expect(richEditable(md)).toBe(true)
  })

  test.each([
    '| a | b |\n|---|---|\n| 1 | 2 |',
    '| Name | Qty |\n| --- | ---: |\n| apple | 3 |',
    '| a | b |\n|:--|:-:|\n| l | c |',
    '| **bold** | `code` | [l](https://x.io) |\n|---|---|---|\n| x | y | z |',
    '| a |\n|---|\n| pipe \\| inside |',
    '| a | b |\n|---|---|\n| 1 |  |',
    'Intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nOutro',
  ])('tables keep their meaning (alignment, escapes, inline marks): %j', (md) => {
    expect(richEditable(md)).toBe(true)
  })

  test.each([
    '- [ ] task',
    'a <b>html</b> tag',
    '1\\. not a list',
  ])('meaning would change, so not rich-editable: %j', (md) => {
    expect(richEditable(md)).toBe(false)
  })

  test('empty body is rich-editable', () => {
    expect(richEditable('')).toBe(true)
  })
})
