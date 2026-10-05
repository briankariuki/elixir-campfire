// MessagePager: loads older/newer pages of messages as the user scrolls near either end of the
// message list. Put on an empty element inside the scrolling `.messages` container, next to (not
// around) the message stream, with `data-load-older` / `data-load-newer` holding the event names
// (the attributes are absent when there is nothing more to load that way).
//
// This replaces LiveView's `phx-viewport-top/bottom` on the stream on purpose: that hook pushes
// its events from the stream container and sends two `load_older` per scroll, and while an event
// is in flight LiveView locks the pushing element and patches a clone of it. With two replies
// overlapping, the stream inserts of the first end up applied without their stream positions when
// the clone is merged back, and pages end up in the wrong order. Here the events come from this
// element (never the stream or one of its ancestors) and only one is in flight at a time.

const THRESHOLD_PX = 300

export default {
  mounted() {
    this.scroller = this.el.parentElement
    this.loading = false
    this.onScroll = () => this.check()
    this.scroller.addEventListener("scroll", this.onScroll, {passive: true})
  },

  destroyed() {
    this.scroller?.removeEventListener("scroll", this.onScroll)
  },

  check() {
    if (this.loading) return

    const {scrollTop, scrollHeight, clientHeight} = this.scroller
    const olderEvent = this.el.dataset.loadOlder
    const newerEvent = this.el.dataset.loadNewer

    if (olderEvent && scrollTop <= THRESHOLD_PX) {
      this.load(olderEvent)
    } else if (newerEvent && scrollHeight - scrollTop - clientHeight <= THRESHOLD_PX) {
      this.load(newerEvent)
    }
  },

  load(event) {
    const heightBefore = this.scroller.scrollHeight
    this.loading = true

    const done = () => {
      this.loading = false
      // Still near an end after a page came in (e.g. a short list): keep going, but only while
      // pages actually add content
      if (this.scroller.scrollHeight !== heightBefore) requestAnimationFrame(() => this.check())
    }

    this.pushEvent(event, {}).then(done, done)
  },
}
