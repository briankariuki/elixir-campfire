// MessageList: put on the scrolling `.messages` container (phx-update="stream").
//
// - Scrolls to the bottom on mount (or centers a `.search-highlight` message).
// - On updates: stays pinned to the bottom if the user was within 100px of it; otherwise shows the
//   `.message-area__return-to-latest` button (looked up next to the container). When older messages
//   are prepended it keeps the visible messages where they were.
// - Recomputes `message--threaded` (same author within 5 minutes) and `message--first-of-day`
//   (local calendar date differs from the previous message) on every `.message`.
// - Plays `/play` sounds on the server's `play_sound` push_event: `{url}`.

const NEAR_BOTTOM_PX = 100
const THREADING_WINDOW_MS = 5 * 60 * 1000

export default {
  mounted() {
    this.returnButton = this.el.parentElement.querySelector(".message-area__return-to-latest")
    this.returnButton?.addEventListener("click", () => this.scrollToBottom())

    // Opening a permalink shows the linked message, not the bottom (a pinned list would jump to it)
    const highlighted = this.el.querySelector(".search-highlight")
    this.pinned = !highlighted

    this.el.addEventListener("scroll", () => {
      this.pinned = this.isNearBottom()
      if (this.pinned) this.toggleReturnButton(false)
    }, {passive: true})

    // Stay at the bottom when the container shrinks (e.g. the composer grows a line)
    this.resizeObserver = new ResizeObserver(() => this.pinned && this.scrollToBottom())
    this.resizeObserver.observe(this.el)

    this.handleEvent("play_sound", ({url}) => new Audio(url).play().catch(() => {}))

    // LiveView resets the class attribute whenever it patches a message, so re-apply our classes
    // after any DOM change (toggling a class to its current state doesn't trigger the observer again)
    this.mutationObserver = new MutationObserver(() => this.format())
    this.mutationObserver.observe(this.el, {childList: true, subtree: true, attributeFilter: ["class"]})
    this.format()

    highlighted ? highlighted.scrollIntoView({block: "center"}) : this.scrollToBottom()
  },

  beforeUpdate() {
    this.wasNearBottom = this.isNearBottom()
    this.lastMessage = this.lastMessageEl()
    // Remember where the first visible message sits, to restore it if items get prepended
    const top = this.el.getBoundingClientRect().top
    this.anchor = this.messages().find(el => el.getBoundingClientRect().bottom > top)
    this.anchorTop = this.anchor?.getBoundingClientRect().top
  },

  updated() {
    this.format()

    if (this.wasNearBottom) {
      this.scrollToBottom()
    } else {
      if (this.anchor?.isConnected) {
        // Keep the first visible message in place when older ones are prepended
        // (a no-op if nothing moved or the browser's scroll anchoring already handled it)
        this.el.scrollTop += this.anchor.getBoundingClientRect().top - this.anchorTop
      }
      if (this.lastMessageEl() !== this.lastMessage) this.toggleReturnButton(true)
    }
  },

  destroyed() {
    this.resizeObserver?.disconnect()
    this.mutationObserver?.disconnect()
  },

  messages() {
    return Array.from(this.el.querySelectorAll(".message[data-message-timestamp]"))
  },

  lastMessageEl() {
    const messages = this.messages()
    return messages[messages.length - 1]
  },

  isNearBottom() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight <= NEAR_BOTTOM_PX
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
    // Again after observers (e.g. LocalTime filling in <time> text) have run
    requestAnimationFrame(() => this.el.scrollTop = this.el.scrollHeight)
    this.toggleReturnButton(false)
  },

  toggleReturnButton(show) {
    if (this.returnButton) this.returnButton.hidden = !show
  },

  format() {
    let previous = null

    for (const message of this.messages()) {
      const time = Number(message.dataset.messageTimestamp)
      const previousTime = previous && Number(previous.dataset.messageTimestamp)

      const firstOfDay = !previous || new Date(time).toDateString() !== new Date(previousTime).toDateString()
      const threaded = !!previous &&
        previous.dataset.userId === message.dataset.userId &&
        Math.abs(time - previousTime) <= THREADING_WINDOW_MS

      message.classList.toggle("message--first-of-day", firstOfDay)
      message.classList.toggle("message--threaded", threaded)
      previous = message
    }
  },
}
