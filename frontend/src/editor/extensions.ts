import { Markdown } from '@tiptap/markdown'
import StarterKit from '@tiptap/starter-kit'

// Shared by the inline body editor and its round-trip tests.
export const bodyExtensions = [StarterKit, Markdown]
