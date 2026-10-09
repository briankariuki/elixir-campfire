// The composer's `@` mention menu (used by the Composer hook).
//
// Typing `@` (at the start or after whitespace) plus up to two words of letters opens a listbox of
// the room's members whose name, or a word of it, starts with that text. The members come from the
// server (`mention_search` with a reply), so big rooms are fine and only members of the room are
// offered. Choosing one replaces the `@query` with `@Full Name ` (the domain resolves `@Full Name`
// against the room's members when the message is saved).
//
// The menu element is rendered by the server with `phx-update="ignore"`; this fills it with
// `button[role=option]` items (original `.autocomplete__*` styles) and keeps the textarea's ARIA
// combobox state (`aria-expanded`, `aria-activedescendant`) in sync.

const TRIGGER = /(^|[\s(])@([\p{L}\p{N}._'’-]*(?: [\p{L}\p{N}._'’-]*)?)$/u
const SEARCH_DEBOUNCE_MS = 80

// The `@query` ending at `caret`: {start (index of the "@"), query} or null
export function findMention(value, caret) {
  const match = TRIGGER.exec(value.slice(0, caret))
  if (!match) return null
  return {start: caret - match[2].length - 1, query: match[2]}
}

export default class MentionMenu {
  // `search(query, onReply)` asks the server; `onInsert()` runs after the text changed
  constructor({textarea, menu, search, onInsert}) {
    this.textarea = textarea
    this.menu = menu
    this.search = search
    this.onInsert = onInsert
    this.items = []
    this.active = -1
    this.current = null
    this.seq = 0
    this.timer = null
    // A query with no matches: longer queries starting with it can't match either
    this.deadQuery = null

    textarea.setAttribute("aria-haspopup", "listbox")
    textarea.setAttribute("aria-autocomplete", "list")
    textarea.setAttribute("aria-controls", menu.id)
    this.sync()

    // Keep the textarea focused when clicking in the menu
    this.onMouseDown = event => event.preventDefault()
    this.onClick = event => {
      const index = this.indexOf(event.target)
      if (index >= 0) this.insert(this.items[index])
    }
    this.onMouseOver = event => {
      const index = this.indexOf(event.target)
      if (index >= 0 && index !== this.active) this.setActive(index)
    }
    menu.addEventListener("mousedown", this.onMouseDown)
    menu.addEventListener("click", this.onClick)
    menu.addEventListener("mouseover", this.onMouseOver)
  }

  destroy() {
    clearTimeout(this.timer)
    this.menu.removeEventListener("mousedown", this.onMouseDown)
    this.menu.removeEventListener("click", this.onClick)
    this.menu.removeEventListener("mouseover", this.onMouseOver)
  }

  get open() {
    return !this.menu.hidden && this.items.length > 0
  }

  // Re-evaluates the text before the caret: call after input, clicks and caret keys
  update() {
    const {selectionStart, selectionEnd, value} = this.textarea
    const mention = selectionStart === selectionEnd ? findMention(value, selectionStart) : null

    if (!mention) {
      this.deadQuery = null
      return this.close()
    }
    if (this.deadQuery !== null && mention.query.startsWith(this.deadQuery)) return this.close()
    this.current = mention
    this.deadQuery = null

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.request(mention.query), SEARCH_DEBOUNCE_MS)
  }

  request(query) {
    const seq = ++this.seq
    this.search(query, reply => {
      // Stale (the user typed on, or closed the menu)
      if (seq !== this.seq || !this.current) return

      const items = (reply && reply.users) || []
      if (items.length === 0) {
        this.deadQuery = query
        this.close()
      } else {
        this.items = items
        this.render()
      }
    })
  }

  close() {
    clearTimeout(this.timer)
    this.seq++
    this.current = null
    this.items = []
    this.active = -1
    this.menu.hidden = true
    this.menu.replaceChildren()
    this.sync()
  }

  render() {
    this.menu.replaceChildren(...this.items.map((item, index) => this.option(item, index)))
    this.menu.hidden = false
    this.setActive(0)
  }

  option(item, index) {
    const button = document.createElement("button")
    button.type = "button"
    button.id = `${this.menu.id}-option-${index}`
    button.className = "btn autocomplete__btn autocomplete__item"
    button.setAttribute("role", "option")
    button.setAttribute("aria-selected", "false")
    // `tabindex=-1`: the textarea keeps focus, the options are driven by the arrow keys
    button.tabIndex = -1

    const figure = document.createElement("figure")
    figure.className = "avatar"
    const img = document.createElement("img")
    img.src = item.avatar
    img.alt = ""
    img.width = img.height = 48
    img.setAttribute("aria-hidden", "true")
    figure.append(img)

    const name = document.createElement("span")
    name.className = "overflow-ellipsis"
    name.textContent = item.name

    button.append(figure, name)
    return button
  }

  indexOf(target) {
    const option = target.closest?.("[role=option]")
    return option ? Array.prototype.indexOf.call(this.menu.children, option) : -1
  }

  setActive(index) {
    this.active = index
    Array.from(this.menu.children).forEach((option, i) => {
      option.setAttribute("aria-selected", String(i === index))
    })
    this.menu.children[index]?.scrollIntoView({block: "nearest"})
    this.sync()
  }

  // ARIA combobox state on the textarea (re-applied by the hook after LiveView patches it)
  sync() {
    const open = this.open
    this.textarea.setAttribute("aria-expanded", String(open))
    if (open && this.active >= 0) {
      this.textarea.setAttribute("aria-activedescendant", `${this.menu.id}-option-${this.active}`)
    } else {
      this.textarea.removeAttribute("aria-activedescendant")
    }
  }

  // Handles a keydown while the menu is open; returns whether it consumed the key
  handleKey(event) {
    if (!this.open) return false

    switch (event.key) {
      case "ArrowDown":
        this.setActive((this.active + 1) % this.items.length)
        break
      case "ArrowUp":
        this.setActive((this.active - 1 + this.items.length) % this.items.length)
        break
      case "Enter":
      case "Tab":
        this.insert(this.items[this.active])
        break
      case "Escape":
        // Don't let it reach window handlers (e.g. cancelling an edit)
        event.stopPropagation()
        this.close()
        break
      default:
        return false
    }

    event.preventDefault()
    return true
  }

  insert(item) {
    if (!item || !this.current) return
    const {value, selectionStart} = this.textarea
    const {start} = this.current
    const text = `@${item.name} `

    this.close()
    this.deadQuery = null
    this.textarea.value = value.slice(0, start) + text + value.slice(selectionStart)
    this.textarea.setSelectionRange(start + text.length, start + text.length)
    this.textarea.focus()
    this.onInsert()
  }
}
