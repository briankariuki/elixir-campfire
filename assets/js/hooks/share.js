// Share: shares the attachment file (`data-share-url`, fetched as a Blob, typed `data-share-type`) with the Web Share API,
// like the original's web-share controller. The button is rendered `hidden` and only shown when the
// browser can share files (mostly mobile).

const SHAREABLE = () => typeof navigator.canShare === "function" && typeof navigator.share === "function"

export default {
  mounted() {
    this.el.hidden = !this.canShareFiles()

    this.el.addEventListener("click", async event => {
      event.preventDefault()
      event.stopPropagation()

      try {
        const file = await this.fetchFile()
        await navigator.share({files: [file], title: this.el.dataset.shareTitle})
      } catch (error) {
        // Dismissing the share sheet is not an error
        if (error?.name !== "AbortError") console.error("Share failed", error)
      }
    })
  },

  canShareFiles() {
    if (!SHAREABLE()) return false

    try {
      return navigator.canShare({files: [new File([""], "file.txt", {type: "text/plain"})]})
    } catch {
      return false
    }
  },

  async fetchFile() {
    const response = await fetch(this.el.dataset.shareUrl, {credentials: "same-origin"})
    if (!response.ok) throw new Error(`Download failed (${response.status})`)

    const blob = await response.blob()
    const name = this.el.dataset.shareTitle || `Campfire_${Math.random().toString(36).slice(2)}`
    return new File([blob], name, {type: this.el.dataset.shareType || blob.type})
  },
}
