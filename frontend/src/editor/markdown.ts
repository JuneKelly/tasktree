import { Editor } from '@tiptap/react'
import { Marked } from 'marked'
import { bodyExtensions } from './extensions'

// Separate instance so editor-side marked configuration can't affect the comparison.
const reference = new Marked()

const toHtml = (md: string) =>
  (reference.parse(md, { async: false }) as string).replace(/>\s+</g, '><').trim()

/** Markdown after a trip through the rich editor (parse, then serialize). */
export function roundTrip(md: string): string {
  const editor = new Editor({ extensions: bodyExtensions, content: md, contentType: 'markdown' })
  try {
    return editor.getMarkdown()
  } finally {
    editor.destroy()
  }
}

/**
 * True when editing `md` in the rich editor can't change what it means: the original and
 * its round trip render to the same HTML. Cosmetic rewrites (`*` vs `-` bullets, `_x_` vs
 * `*x*`) pass; tables, task lists, raw HTML and some escapes don't, so those bodies are
 * edited as raw markdown instead.
 */
export function richEditable(md: string): boolean {
  if (md.trim() === '') return true
  return toHtml(md) === toHtml(roundTrip(md))
}
