// Copy: on click, copies `data-copy` to the clipboard and briefly flashes `.btn--success`.

export default {
  mounted() {
    this.el.addEventListener("click", async event => {
      event.preventDefault()

      try {
        await navigator.clipboard.writeText(this.el.dataset.copy)
      } catch {
        return
      }

      this.el.classList.remove("btn--success")
      void this.el.offsetWidth // restart the animation
      this.el.classList.add("btn--success")
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.el.classList.remove("btn--success"), 1000)
    })
  },

  destroyed() {
    clearTimeout(this.timer)
  },
}
