import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

const plugins = [remarkGfm]

/** Rendered note body. GFM adds tables, strikethrough, autolinks and checklists. */
export const MarkdownView = ({ children }: { children: string }) => (
  <Markdown remarkPlugins={plugins}>{children}</Markdown>
)
