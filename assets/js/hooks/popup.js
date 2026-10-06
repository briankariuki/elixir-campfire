// Popup: behaviour for the translation `<details data-popup>` menus (the original's Stimulus
// `popup` controller). It's delegated at the document level instead of a LiveView hook so it also
// works on controller-rendered pages (sign in, join, first run), and keeps working when LiveView
// patches the DOM.
//
//  - opening/closing flips the menu above the button when it's close to the bottom of the screen
//    (`data-popup-orientation-top-class`) and caps its width to the space on the right
//  - Esc and a click outside close every open menu

const BOTTOM_THRESHOLD = 90

function orient(details) {
  const menu = details.querySelector("[data-popup-menu]")
  if (!menu) return

  const rect = menu.getBoundingClientRect()
  const topClass = details.dataset.popupOrientationTopClass
  if (topClass) details.classList.toggle(topClass, window.innerHeight - rect.bottom < BOTTOM_THRESHOLD)
  menu.style.setProperty("--max-width", `${window.innerWidth - rect.left}px`)
}

function closeAll(except = null) {
  document.querySelectorAll("details[data-popup][open]").forEach(details => {
    if (!except || !details.contains(except)) details.open = false
  })
}

// `toggle` doesn't bubble, so listen in the capture phase
document.addEventListener("toggle", ({target}) => {
  if (target instanceof HTMLDetailsElement && target.hasAttribute("data-popup")) orient(target)
}, true)

document.addEventListener("click", ({target}) => closeAll(target))
document.addEventListener("keydown", ({key}) => { if (key === "Escape") closeAll() })
