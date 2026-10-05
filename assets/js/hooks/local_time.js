// LocalTime: formats every `<time datetime="ISO8601" data-format="time|date|datetime">` inside the
// hooked element in the viewer's locale and time zone, now and whenever the DOM changes.
// The full date and time goes into the `title`.

const formatters = {
  time: new Intl.DateTimeFormat(undefined, {timeStyle: "short"}),
  date: new Intl.DateTimeFormat(undefined, {dateStyle: "long"}),
  datetime: new Intl.DateTimeFormat(undefined, {dateStyle: "short", timeStyle: "short"}),
}

export function formatLocalTimes(root) {
  for (const el of root.querySelectorAll("time[datetime][data-format]")) {
    const date = new Date(el.getAttribute("datetime"))
    const formatter = formatters[el.dataset.format]
    if (!formatter || isNaN(date)) continue

    const text = formatter.format(date)
    const title = formatters.datetime.format(date)
    // Only write when different, so our own changes don't retrigger the observer forever
    if (el.textContent !== text) el.textContent = text
    if (el.title !== title) el.title = title
  }
}

export default {
  mounted() {
    formatLocalTimes(this.el)
    this.observer = new MutationObserver(() => formatLocalTimes(this.el))
    this.observer.observe(this.el, {childList: true, subtree: true, characterData: true})
  },

  destroyed() {
    this.observer?.disconnect()
  },
}
