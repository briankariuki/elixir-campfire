// Visibility: tells the LiveView whether the tab is being looked at, for presence/read tracking.
// Pushes "visible" immediately when the page becomes visible, and "hidden" once it has stayed
// hidden for 5 seconds.

const HIDDEN_DELAY_MS = 5000

export default {
  mounted() {
    this.onChange = () => {
      clearTimeout(this.timer)

      if (document.visibilityState === "visible") {
        this.pushEvent("visible", {})
      } else {
        this.timer = setTimeout(() => this.pushEvent("hidden", {}), HIDDEN_DELAY_MS)
      }
    }

    document.addEventListener("visibilitychange", this.onChange)
    if (document.visibilityState !== "visible") this.onChange()
  },

  destroyed() {
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onChange)
  },
}
