import { TableKit } from '@tiptap/extension-table'
import { Markdown } from '@tiptap/markdown'
import StarterKit from '@tiptap/starter-kit'

// Shared by the inline body editor and its round-trip guard.
export const bodyExtensions = [StarterKit, TableKit, Markdown]
