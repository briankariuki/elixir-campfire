// The composer's formatting toolbar (used by the Composer hook).
//
// The message renderer (lib/campfire_web/message_body.ex) understands a small Markdown-like
// subset; each toolbar button inserts that syntax into the textarea:
//
//   bold **x**, italic _x_, strike ~~x~~, highlight ==x==, code `x`  - wrap the selection (or insert
//       an empty pair with the caret between); applied again to wrapped text they unwrap. A
//       multi-line selection is wrapped line by line, since a marker can't span lines.
//   heading "# ", quote "> ", bullets "- ", numbers "1. "            - prefix the selected lines (the
//       current line without a selection); applied again they remove the prefix.
//   code block ```\n...\n```                                          - fence the selected lines; inside
//       a fence it removes the fence.
//
// `formatEdit/4` is pure (value + selection in, replacement out); `applyEdit/2` performs the
// replacement through the browser's editing commands so Undo keeps working and the `input` event
// fires (the Composer hook then resizes, saves the draft and sends "typing").
//
// The toolbar element and its toggle button are rendered by the server with `phx-update="ignore"`;
// the `hidden` attribute is the open/closed state. While it is open Enter inserts a newline and
// only Cmd/Ctrl+Enter sends (see the Composer hook).

const INLINE = {bold: "**", italic: "_", strike: "~~", highlight: "==", code: "`"}
const FENCE_OPEN = /^```[\w+#.-]{0,30}[ \t]*$/
const FENCE_CLOSE = /^```[ \t]*$/
const SHORTCUTS = {b: "bold", i: "italic"}

// The edit for `format` applied to the selection [start, end) of `value`:
// {from, to, text, selStart, selEnd}: replace [from, to) with `text`, then select [selStart, selEnd).
// Returns null for an unknown format.
export function formatEdit(value, start, end, format) {
  if (format in INLINE) return inlineEdit(value, start, end, INLINE[format])

  switch (format) {
    case "heading":
      return lineEdit(value, start, end, lines =>
        togglePrefix(lines, /^# /, line => `# ${line}`))
    case "quote":
      return lineEdit(value, start, end, quoteLines)
    case "bullet":
      return lineEdit(value, start, end, lines =>
        togglePrefix(lines, /^[-*] /, line => `- ${line.replace(/^\d+\. /, "")}`))
    case "number":
      return lineEdit(value, start, end, numberLines)
    case "codeblock":
      return codeBlockEdit(value, start, end)
    default:
      return null
  }
}

function inlineEdit(value, start, end, marker) {
  const len = marker.length
  let selected = value.slice(start, end)

  // Only whitespace selected: act at the end of it
  if (selected.trim() === "") {
    start = end
    selected = ""
  }

  if (selected === "") {
    const empty = value.slice(0, start).endsWith(marker) && value.slice(start).startsWith(marker)
    if (empty) return {from: start - len, to: start + len, text: "", selStart: start - len, selEnd: start - len}
    return {from: start, to: start, text: marker + marker, selStart: start + len, selEnd: start + len}
  }

  // The marker has to hug the text: leave the selection's outer whitespace alone
  const from = start + (selected.length - selected.trimStart().length)
  const to = end - (selected.length - selected.trimEnd().length)
  const inner = value.slice(from, to)

  // Selected text inside a pair of markers: remove the pair
  if (!inner.includes("\n") && value.slice(0, from).endsWith(marker) && value.slice(to).startsWith(marker)) {
    return {from: from - len, to: to + len, text: inner, selStart: from - len, selEnd: from - len + inner.length}
  }

  const parts = inner.split("\n").map(line => {
    const core = line.trim()
    const lead = core === "" ? line : line.slice(0, line.indexOf(core))
    return {core, lead, trail: line.slice(lead.length + core.length)}
  })
  const cores = parts.filter(part => part.core !== "")
  const wrapped = cores.every(({core}) => core.length > 2 * len && core.startsWith(marker) && core.endsWith(marker))

  const text = parts
    .map(({core, lead, trail}) => {
      if (core === "") return lead
      return lead + (wrapped ? core.slice(len, core.length - len) : marker + core + marker) + trail
    })
    .join("\n")

  return {from, to, text, selStart: from, selEnd: from + text.length}
}

// [from, to) of the lines the selection touches (not the next line when it ends right after a "\n")
function lineRange(value, start, end) {
  const from = start === 0 ? 0 : value.lastIndexOf("\n", start - 1) + 1
  const last = end > start && value[end - 1] === "\n" ? end - 1 : end
  const to = value.indexOf("\n", last)
  return [from, to === -1 ? value.length : to]
}

function lineEdit(value, start, end, transform) {
  const [from, to] = lineRange(value, start, end)
  const block = value.slice(from, to)
  const text = transform(block.split("\n")).join("\n")

  if (start === end) {
    // One line: the caret keeps its place in the text
    const caret = Math.min(Math.max(start + text.length - block.length, from), from + text.length)
    return {from, to, text, selStart: caret, selEnd: caret}
  }
  return {from, to, text, selStart: from, selEnd: from + text.length}
}

const blank = line => line.trim() === ""

// Removes `prefix` from every line when all the text lines have it, else adds `add(line)` to them.
// Blank lines are left alone, unless the block is that single blank line.
function togglePrefix(lines, prefix, add) {
  const content = lines.filter(line => !blank(line))
  if (content.length > 0 && content.every(line => prefix.test(line))) {
    return lines.map(line => line.replace(prefix, ""))
  }
  return lines.map(line => (blank(line) && lines.length > 1 ? line : add(line)))
}

function quoteLines(lines) {
  const content = lines.filter(line => !blank(line))
  if (content.length > 0 && content.every(line => /^>( |$)/.test(line))) {
    return lines.map(line => line.replace(/^> ?/, ""))
  }
  // A blank line inside a quote stays in it (">")
  return lines.map(line => (blank(line) && lines.length > 1 ? ">" : `> ${line}`))
}

function numberLines(lines) {
  const content = lines.filter(line => !blank(line))
  if (content.length > 0 && content.every(line => /^\d+\. /.test(line))) {
    return lines.map(line => line.replace(/^\d+\. /, ""))
  }

  let number = 0
  return lines.map(line => {
    if (blank(line) && lines.length > 1) return line
    number += 1
    return `${number}. ${line.replace(/^[-*] /, "")}`
  })
}

// The fenced block (``` .. ```) containing `position`: {from, to, inner} or null
function fenceAt(value, position) {
  const lines = value.split("\n")
  const offsets = []
  lines.reduce((offset, line) => (offsets.push(offset), offset + line.length + 1), 0)

  for (let i = 0; i < lines.length; i++) {
    if (!FENCE_OPEN.test(lines[i])) continue

    const close = lines.findIndex((line, j) => j > i && FENCE_CLOSE.test(line))
    if (close === -1) continue

    const from = offsets[i]
    const to = offsets[close] + lines[close].length
    if (position >= from && position <= to) return {from, to, inner: lines.slice(i + 1, close).join("\n")}
    i = close
  }
  return null
}

function codeBlockEdit(value, start, end) {
  const fence = fenceAt(value, start)
  if (fence) {
    return {from: fence.from, to: fence.to, text: fence.inner, selStart: fence.from, selEnd: fence.from + fence.inner.length}
  }

  const [from, to] = lineRange(value, start, end)
  const block = value.slice(from, to)
  const inner = from + 4
  return {from, to, text: "```\n" + block + "\n```", selStart: inner, selEnd: inner + block.length}
}

// Performs the edit as the user typing would: Undo works and `input` fires
export function applyEdit(textarea, {from, to, text, selStart, selEnd}) {
  textarea.focus()
  textarea.setSelectionRange(from, to)

  let done = false
  try {
    done = text === "" ? document.execCommand("delete") : document.execCommand("insertText", false, text)
  } catch (_error) {
    done = false
  }

  if (!done) {
    textarea.setRangeText(text, from, to, "end")
    textarea.dispatchEvent(new Event("input", {bubbles: true}))
  }
  textarea.setSelectionRange(selStart, selEnd)
}

export default class Toolbar {
  constructor({textarea, toolbar, toggle}) {
    this.textarea = textarea
    this.toolbar = toolbar
    this.toggleButton = toggle

    // Keep the selection and focus in the textarea when pressing a button
    this.onMouseDown = event => {
      if (event.target.closest("button")) event.preventDefault()
    }
    this.onClick = event => {
      const button = event.target.closest("button[data-format]")
      if (button && !button.disabled) this.apply(button.dataset.format)
    }
    this.onToggle = () => {
      this.toggle()
      this.textarea.focus()
    }

    toolbar.addEventListener("mousedown", this.onMouseDown)
    toolbar.addEventListener("click", this.onClick)
    toggle?.addEventListener("mousedown", this.onMouseDown)
    toggle?.addEventListener("click", this.onToggle)
  }

  destroy() {
    this.toolbar.removeEventListener("mousedown", this.onMouseDown)
    this.toolbar.removeEventListener("click", this.onClick)
    this.toggleButton?.removeEventListener("mousedown", this.onMouseDown)
    this.toggleButton?.removeEventListener("click", this.onToggle)
  }

  // Shown (the toggle is desktop-only; the stylesheet hides the toolbar elsewhere)
  get open() {
    return !this.toolbar.hidden && getComputedStyle(this.toolbar).display !== "none"
  }

  toggle() {
    this.setOpen(this.toolbar.hidden)
  }

  close() {
    this.setOpen(false)
  }

  setOpen(open) {
    this.toolbar.hidden = !open
    this.toggleButton?.setAttribute("aria-expanded", String(open))
  }

  setDisabled(disabled) {
    this.toolbar.querySelectorAll("button").forEach(button => (button.disabled = disabled))
    if (this.toggleButton) this.toggleButton.disabled = disabled
  }

  apply(format) {
    const {value, selectionStart, selectionEnd} = this.textarea
    const edit = formatEdit(value, selectionStart, selectionEnd, format)
    if (edit) applyEdit(this.textarea, edit)
  }

  // Cmd/Ctrl+B and Cmd/Ctrl+I. Returns whether the key was handled.
  handleKey(event) {
    if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) return false
    const format = SHORTCUTS[event.key?.toLowerCase()]
    if (!format) return false

    event.preventDefault()
    this.apply(format)
    return true
  }
}
