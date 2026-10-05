// Filter: put on a container holding an `input[type=search]` and a list (`[data-filter-list]`, or the
// container itself) of `li[data-value]` items (the member list of the room form). Typing marks the
// list `.filter--active` and every item whose
// lowercased `data-value` contains the (lowercased) query `.selected`; filters.css hides the others.
//
// Items are only hidden, never removed, so the form still submits every checkbox. When LiveView
// patches the form it resets the classes and the (unfocused) search input to the server-rendered
// empty value, so `updated` puts the query back and re-applies the filter.

export default {
  mounted() {
    this.query = ""
    this.listen()
    this.apply()
  },

  updated() {
    this.listen()
    if (this.input && this.input.value !== this.query) this.input.value = this.query
    this.apply()
  },

  // The input can be replaced by a patch (or appear once the list grows past the threshold)
  listen() {
    const input = this.el.querySelector("input[type=search]")
    if (input === this.input) return
    this.input = input
    this.input?.addEventListener("input", () => {
      this.query = this.input.value
      this.apply()
    })
  },

  apply() {
    const query = this.query.trim().toLowerCase()

    const list = this.el.querySelector("[data-filter-list]") || this.el

    list.classList.toggle("filter--active", query !== "")

    for (const item of list.querySelectorAll("li[data-value]")) {
      item.classList.toggle("selected", query !== "" && item.dataset.value.includes(query))
    }
  },
}
