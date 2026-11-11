import { EditorContent, useEditor } from '@tiptap/react'
import { useEffect, useRef } from 'react'
import { bodyExtensions } from './extensions'

interface Props {
  label: string
  initial: string
  onChange: (markdown: string) => void
  onFocus: () => void
  onBlur: () => void
}

const blurActive = () => (document.activeElement as HTMLElement | null)?.blur()

/**
 * WYSIWYG body editor. Loading markdown can itself emit an update with a normalised
 * serialisation (e.g. `*` bullets become `-`), so any content that serialises the same as
 * the freshly loaded document is reported as the untouched original. Opening and closing
 * a note therefore never rewrites it.
 */
export function RichBodyEditor({ label, initial, onChange, onFocus, onBlur }: Props) {
  // TipTap captures callbacks at creation; route through refs so they stay current.
  const cb = useRef({ onChange, onFocus, onBlur })
  useEffect(() => {
    cb.current = { onChange, onFocus, onBlur }
  })
  // Serialisation of the document as loaded. TipTap can emit an update while parsing the
  // markdown, before onCreate; that update is part of loading, not a user edit.
  const loaded = useRef<string | null>(null)
  const created = useRef(false)

  const editor = useEditor({
    extensions: bodyExtensions,
    content: initial,
    contentType: 'markdown',
    autofocus: 'end',
    editorProps: { attributes: { 'aria-label': label, class: 'body-rich md' } },
    onCreate: ({ editor }) => {
      created.current = true
      loaded.current ??= editor.getMarkdown()
    },
    onUpdate: ({ editor }) => {
      const md = editor.getMarkdown()
      if (!created.current) {
        loaded.current = md
        return
      }
      cb.current.onChange(md === loaded.current ? initial : md)
    },
    onFocus: () => cb.current.onFocus(),
    onBlur: () => cb.current.onBlur(),
  })

  return (
    <div onKeyDown={(e) => e.key === 'Escape' && blurActive()}>
      <EditorContent editor={editor} />
    </div>
  )
}

/** Raw markdown fallback for bodies the rich editor can't round-trip without changing them. */
export function RawBodyEditor({ label, initial, onChange, onFocus, onBlur }: Props) {
  return (
    <div className="body-raw">
      <p className="muted small">
        Editing as markdown: this note contains formatting the rich editor would change.
      </p>
      <textarea
        aria-label={label}
        autoFocus
        defaultValue={initial}
        rows={Math.max(3, initial.split('\n').length + 1)}
        onFocus={onFocus}
        onBlur={onBlur}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => e.key === 'Escape' && blurActive()}
      />
    </div>
  )
}
