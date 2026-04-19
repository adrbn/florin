'use client'
import { useEffect } from 'react'
import { usePrivacy } from './context'

// Only tag text nodes that clearly contain a currency amount — i.e. a digit
// alongside a currency symbol. This avoids blurring dates, counts, IDs, or
// payee descriptions that happen to contain numbers.
const CURRENCY_SYMBOL_RE = /[€$£¥]/

function markAmountNodes(root: Node) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const text = node.nodeValue ?? ''
      if (!CURRENCY_SYMBOL_RE.test(text)) return NodeFilter.FILTER_REJECT
      if (!/\d/.test(text)) return NodeFilter.FILTER_REJECT
      const parent = (node as Text).parentElement
      if (!parent) return NodeFilter.FILTER_REJECT
      const tag = parent.tagName
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'INPUT' || tag === 'TEXTAREA') {
        return NodeFilter.FILTER_REJECT
      }
      return NodeFilter.FILTER_ACCEPT
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
