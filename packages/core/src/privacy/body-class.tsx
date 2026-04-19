'use client'
import { useEffect } from 'react'
import { usePrivacy } from './context'

// Matches any run of digits with optional decimal/thousand separators — i.e.
// anything that could be an amount. Currency symbol is not required since some
// renderings show the number alone (table cells, chart axes).
const AMOUNT_RE = /[-−]?\d[\d\s.,'\u00a0]*/

function markAmountNodes(root: Node) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const text = node.nodeValue ?? ''
      if (!AMOUNT_RE.test(text)) return NodeFilter.FILTER_REJECT
      // Skip SCRIPT/STYLE text and nodes already inside an input/textarea.
      const parent = (node as Text).parentElement
      if (!parent) return NodeFilter.FILTER_REJECT
      const tag = parent.tagName
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'INPUT' || tag === 'TEXTAREA') {
        return NodeFilter.FILTER_REJECT
      }
      // Heuristic: require at least 2 digits OR presence of currency symbol so
      // things like standalone page numbers aren't blurred. Adjust over time.
      if (/[€$£¥]/.test(text) || /\d{2,}/.test(text)) return NodeFilter.FILTER_ACCEPT
      return NodeFilter.FILTER_REJECT
    },
  })
  const touched: Element[] = []
  while (walker.nextNode()) {
    const parent = (walker.currentNode as Text).parentElement
    if (parent && !parent.hasAttribute('data-amount')) {
      parent.setAttribute('data-amount', 'auto')
      touched.push(parent)
    }
  }
  return touched
}

function clearAutoMarkers() {
  const auto = document.querySelectorAll('[data-amount="auto"]')
  auto.forEach((el) => el.removeAttribute('data-amount'))
}

export function PrivacyBodyClass() {
  const { hidden } = usePrivacy()
  useEffect(() => {
    const el = document.documentElement
    if (!hidden) {
      el.classList.remove('privacy-hidden')
      clearAutoMarkers()
      return
    }
    el.classList.add('privacy-hidden')
    markAmountNodes(document.body)

    // Re-scan on DOM mutations so navigating between pages keeps amounts hidden.
    const observer = new MutationObserver((mutations) => {
      for (const m of mutations) {
        m.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE || node.nodeType === Node.TEXT_NODE) {
            markAmountNodes(node)
          }
        })
        if (m.type === 'characterData' && m.target.parentElement) {
          markAmountNodes(m.target.parentElement)
        }
      }
    })
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
    })

    return () => {
      observer.disconnect()
      clearAutoMarkers()
    }
  }, [hidden])
  return null
}
