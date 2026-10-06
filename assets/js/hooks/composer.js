// Composer: put on the composer <textarea> (inside the message <form>).
//
// - Enter submits the form (Shift+Enter inserts a newline, and so does Enter while the formatting
//   toolbar is open; ignored while composing with an IME;
//   on touch-only devices Enter is a newline, like the original). Cmd/Ctrl+Enter always submits.
// - Auto-grows with its content (CSS caps it at ~10 lines).
// - Pasted files are uploaded with `this.upload(<data-upload-name || "attachments">, files)`.
// - Pushes "typing" to the LiveView at most once per second while typing, and "stop_typing" when
//   the textarea loses focus or becomes empty.
// - ArrowUp in an empty composer pushes "edit_last".
// - Drafts: the text is kept in localStorage["composer-draft-<data-room-id>"] (debounced), restored
//   on mount when the textarea is empty, and removed once the message was sent.
// - Offline: disabled (textarea, send button, file input) once the socket has been disconnected for
//   5s, enabled again as soon as it reconnects.
// - `@` mention menu (composer_mentions.js, the listbox is `#<data-mention-menu>`); while it is
//   open Enter/Tab insert, ArrowUp/ArrowDown move and Escape closes, so none of them send or edit.
// - Formatting toolbar (composer_toolbar.js; `#<data-toolbar>` opened by `#<data-toolbar-toggle>`): the
//   buttons insert the Markdown-like syntax MessageBody renders (bold, italic, strike, highlight,
//   code, code block, heading, quote, lists, link); Cmd/Ctrl+B and Cmd/Ctrl+I work without it. While
//   the toolbar is open Enter inserts a newline and only Cmd/Ctrl+Enter sends (like the original),
//   and Tab / Shift+Tab indent / outdent a list line. The @mention menu handles its keys first, so
//   Tab picks a mention while it is open.
// - Handles the server's "composer:reset" push_event: clear, resize and refocus.
// - Handles "composer:insert" {text}: prepends text (a reply quote) and focuses after it.

import MentionMenu from "./composer_mentions"
import Toolbar from "./composer_toolbar"
import {clearDraft, loadDraft, saveDraft} from "./composer_draft"

const TYPING_INTERVAL_MS = 1000
const DRAFT_DEBOUNCE_MS = 400
const OFFLINE_DISABLE_MS = 5000

export default {
  mounted() {
    this.lastTypingAt = 0
    this.typingSent = false
    this.draftTimer = null
    this.offlineTimer = null
    this.offline = false
    this.roomId = this.el.dataset.roomId

    const menu = document.getElementById(this.el.dataset.mentionMenu || "")
    this.mentions = menu
      ? new MentionMenu({
          textarea: this.el,
          menu,
          search: (query, onReply) => this.push("mention_search", {query}, onReply),
          onInsert: () => this.changed({mentions: false}),
        })
      : null

    const toolbar = document.getElementById(this.el.dataset.toolbar || "")
    this.toolbar = toolbar
      ? new Toolbar({
          textarea: this.el,
          toolbar,
          toggle: document.getElementById(this.el.dataset.toolbarToggle || ""),
        })
      : null

    this.el.addEventListener("keydown", event => this.keydown(event))
    this.el.addEventListener("input", () => this.changed())
    this.el.addEventListener("click", () => this.mentions?.update())
    this.el.addEventListener("keyup", event => {
      if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) this.mentions?.update()
    })
    this.el.addEventListener("blur", () => {
      this.mentions?.close()
      this.flushDraft()
      this.stopTyping()
    })
    this.el.addEventListener("paste", event => this.paste(event))

    this.handleEvent("composer:reset", () => {
      this.el.value = ""
      this.discardDraft()
      this.mentions?.close()
      this.toolbar?.close()
      // The server broadcast "stopped typing" with the send
      this.typingSent = false
      this.lastTypingAt = 0
      this.resize()
      this.el.focus()
    })

    // Reply: prefill the composer with a quote
    this.handleEvent("composer:insert", ({text}) => {
      this.el.value = text + this.el.value
      this.resize()
      this.scheduleDraftSave()
      this.el.focus()
      this.el.setSelectionRange(text.length, text.length)
    })

    this.restoreDraft()
    this.resize()
  },

  updated() {
    // Switching rooms without a remount: the draft belongs to the room
    if (this.el.dataset.roomId !== this.roomId) {
      this.flushDraft()
      this.roomId = this.el.dataset.roomId
      this.el.value = ""
      this.restoreDraft()
    }

    // LiveView patches reset attributes it doesn't render
    if (this.offline) this.setOffline(true)
    this.mentions?.sync()
    this.resize()
  },

  disconnected() {
    clearTimeout(this.offlineTimer)
    this.offlineTimer = setTimeout(() => this.setOffline(true), OFFLINE_DISABLE_MS)
  },

  reconnected() {
    clearTimeout(this.offlineTimer)
    this.setOffline(false)
    this.restoreDraft()
  },

  destroyed() {
    clearTimeout(this.offlineTimer)
    this.flushDraft()
    this.mentions?.destroy()
    this.toolbar?.destroy()
  },

  keydown(event) {
    if (event.isComposing || event.keyCode === 229) return
    if (this.mentions?.handleKey(event)) return
    if (this.toolbar?.handleKey(event)) return

    if (event.key === "Enter") {
      const modifier = event.metaKey || event.ctrlKey
      const touchOnly = matchMedia("(pointer: coarse)").matches && !matchMedia("(pointer: fine)").matches

      // Cmd/Ctrl+Enter always sends; plain Enter only without Shift, on a pointer device and while
      // the formatting toolbar is closed. Otherwise it is a newline.
      if (!modifier && (event.shiftKey || touchOnly || this.toolbar?.open)) return

      event.preventDefault()
      this.submit()
    } else if (event.key === "ArrowUp" && this.el.value === "") {
      event.preventDefault()
      this.push("edit_last")
    }
  },

  // The text changed by typing, pasting or picking a mention
  changed({mentions = true} = {}) {
    this.resize()
    if (this.el.value === "") this.stopTyping()
    else this.notifyTyping()
    this.scheduleDraftSave()
    if (mentions) this.mentions?.update()
  },

  // With a callback, LiveView ignores push errors (e.g. while disconnected) instead of rejecting
  push(event, payload = {}, onReply = () => {}) {
    this.pushEvent(event, payload, onReply)
  },

  submit() {
    const form = this.el.form
    const hasFiles = form?.querySelector(".composer__file")
    if (form && (this.el.value.trim() !== "" || hasFiles)) form.requestSubmit()
  },

  resize() {
    this.el.style.height = "auto"
    this.el.style.height = `${this.el.scrollHeight}px`
  },

  notifyTyping() {
    const now = Date.now()
    if (now - this.lastTypingAt >= TYPING_INTERVAL_MS) {
      this.lastTypingAt = now
      this.typingSent = true
      this.push("typing")
    }
  },

  stopTyping() {
    if (!this.typingSent) return
    this.typingSent = false
    this.lastTypingAt = 0
    this.push("stop_typing")
  },

  paste(event) {
    const files = Array.from(event.clipboardData?.files || [])
    if (files.length > 0) {
      event.preventDefault()
      this.upload(this.el.dataset.uploadName || "attachments", files)
    }
  },

  // Drafts

  restoreDraft() {
    if (this.el.value !== "") return
    const draft = loadDraft(this.roomId)
    if (draft !== "") {
      this.el.value = draft
      this.resize()
    }
  },

  scheduleDraftSave() {
    clearTimeout(this.draftTimer)
    this.draftTimer = setTimeout(() => this.flushDraft(), DRAFT_DEBOUNCE_MS)
  },

  // Saves a pending change now (nothing is written when there isn't one)
  flushDraft() {
    if (this.draftTimer === null) return
    clearTimeout(this.draftTimer)
    this.draftTimer = null
    saveDraft(this.roomId, this.el.value)
  },

  discardDraft() {
    clearTimeout(this.draftTimer)
    this.draftTimer = null
    clearDraft(this.roomId)
  },

  // Offline

  setOffline(offline) {
    const wasOffline = this.offline
    const refocus = !offline && wasOffline && this.hadFocus
    if (offline && !wasOffline) this.hadFocus = document.activeElement === this.el
    this.offline = offline

    const controls = [this.el, ...(this.el.form?.querySelectorAll("button[type=submit], input[type=file]") || [])]
    controls.forEach(control => (control.disabled = offline))
    this.toolbar?.setDisabled(offline)

    if (offline) {
      this.el.dataset.onlinePlaceholder ??= this.el.placeholder
      this.el.placeholder = "Reconnecting…"
      this.mentions?.close()
    } else if (this.el.dataset.onlinePlaceholder !== undefined) {
      this.el.placeholder = this.el.dataset.onlinePlaceholder
      delete this.el.dataset.onlinePlaceholder
    }

    if (refocus) this.el.focus()
  },
}
