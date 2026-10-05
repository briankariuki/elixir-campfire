// Lightbox: clicking an `a[data-lightbox]` inside the hooked element opens its `href` in the
// global `<dialog class="lightbox">` (rendered by the root layout). The download button uses
// `data-lightbox-download` (falls back to the href). Close with Esc, the × button or a backdrop click.

export default {
  mounted() {
    this.dialog = document.querySelector("dialog.lightbox")
    if (!this.dialog) return

    if (!this.dialog.dataset.lightboxReady) {
      this.dialog.dataset.lightboxReady = "true"
      this.dialog.addEventListener("click", event => {
        if (event.target === this.dialog) this.dialog.close()
      })
      this.dialog.addEventListener("close", () => {
        this.dialog.querySelector(".lightbox__image").removeAttribute("src")
      })
    }

    this.el.addEventListener("click", event => {
      const link = event.target.closest("a[data-lightbox]")
      if (!link || event.metaKey || event.ctrlKey || event.shiftKey) return

      event.preventDefault()
      this.open(link)
    })
  },

  open(link) {
    this.dialog.querySelector(".lightbox__image").src = link.href

    const download = this.dialog.querySelector(".lightbox__btn--download")
    if (download) download.href = link.dataset.lightboxDownload || link.href

    this.dialog.showModal()
  },
}
