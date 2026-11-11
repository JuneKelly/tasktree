import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'
import { clearToken } from '../auth'

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  clearToken()
})

// jsdom has no layout. ProseMirror (TipTap) measures selections to scroll them into view,
// so give it empty geometry.
const emptyRects = () => Object.assign([], { item: () => null }) as unknown as DOMRectList
const emptyRect = () => new DOMRect(0, 0, 0, 0)
Range.prototype.getClientRects = emptyRects
Range.prototype.getBoundingClientRect = emptyRect
Element.prototype.getClientRects = emptyRects
document.elementFromPoint = () => null
