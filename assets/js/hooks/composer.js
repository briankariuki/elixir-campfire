// Composer: put on the composer <textarea> (inside the message <form>).
//
// - Enter submits the form (Shift+Enter inserts a newline; ignored while composing with an IME;
//   on touch-only devices Enter is a newline, like the original). Cmd/Ctrl+Enter always submits.
// - Auto-grows with its content (CSS caps it at ~10 lines).
// - Pasted files are uploaded with `this.upload(<data-upload-name || "attachments">, files)`.
// - Pushes "typing" to the LiveView at most once per second while typing.
// - ArrowUp in an empty composer pushes "edit_last".
// - Handles the server's "composer:reset" push_event: clear, resize and refocus.

const TYPING_INTERVAL_MS = 1000

export default {
  mounted() {
    this.lastTypingAt = 0

    this.el.addEventListener("keydown", event => this.keydown(event))
    this.el.addEventListener("input", () => {
      this.resize()
      this.typing()
    })
    this.el.addEventListener("paste", event => this.paste(event))

    this.handleEvent("composer:reset", () => {
      this.el.value = ""
      this.resize()
      this.el.focus()
    })

    this.resize()
  },

  updated() {
    this.resize()
  },

  keydown(event) {
    if (event.isComposing || event.keyCode === 229) return

    if (event.key === "Enter" && !event.shiftKey) {
      const touchOnly = matchMedia("(pointer: coarse)").matches && !matchMedia("(pointer: fine)").matches
      if (touchOnly && !(event.metaKey || event.ctrlKey)) return

      event.preventDefault()
      this.submit()
    } else if (event.key === "ArrowUp" && this.el.value === "") {
      event.preventDefault()
      this.pushEvent("edit_last", {})
    }
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

  typing() {
    const now = Date.now()
    if (this.el.value !== "" && now - this.lastTypingAt >= TYPING_INTERVAL_MS) {
      this.lastTypingAt = now
      this.pushEvent("typing", {})
    }
  },

  paste(event) {
    const files = Array.from(event.clipboardData?.files || [])
    if (files.length > 0) {
      event.preventDefault()
      this.upload(this.el.dataset.uploadName || "attachments", files)
    }
  },
}
