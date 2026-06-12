// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/peggy"
import topbar from "../vendor/topbar"
import autoComplete from "../vendor/autoComplete"

// Hook wrapping tarekraafat/autoComplete.js. Operates fully client-side:
// selection writes the chosen id into a sibling hidden input and dispatches
// an input event so `phx-change` on the form picks it up naturally —
// no per-field LiveView events required.
//
// Expected DOM:
//   <div class="fieldset ..."> ← outer, `position: relative`
//     <label>
//       <input type="hidden" id="{id}-value" name="..." value="..." />
//       <input id="{id}-input" phx-hook="AutoComplete"
//              data-ac-items='[{"id":1,"label":"..."}]' />
//     </label>
//   </div>
const AutoComplete = {
  mounted() {
    const items = JSON.parse(this.el.dataset.acItems || "[]")
    const emptyText = this.el.dataset.acEmptyText || ""
    // In freetext mode the visible input itself carries the form's
    // `name` — selection writes the item's `id` into it, but the user
    // can also leave any typed value as-is (no companion hidden input,
    // no "no matching selection" warning).
    const freetext = this.el.dataset.acFreetext === "true"
    const dropUp = this.el.dataset.acDropUp === "true"
    const touch = this.el.dataset.acTouch === "true"
    const hiddenId = this.el.id.replace(/-input$/, "-value")
    const hidden = freetext ? null : document.getElementById(hiddenId)
    const warningId = this.el.id.replace(/-input$/, "-warning")
    const warning = freetext ? null : document.getElementById(warningId)
    const hook = this
    const showWarning = (on) => {
      if (!warning) return
      warning.classList.toggle("hidden", !on)
    }
    // Results <ul> is attached to the fieldset div so it sits outside the
    // <label> (clicks on the label re-focus the input, which would fight
    // the library's selection logic) and so `absolute top-full` resolves
    // against the relative fieldset container.
    // Note: the library's `select$1` expects a string selector or a
    // function returning an element — passing a DOM node directly crashes.
    const containerFn = () => this.el.closest(".fieldset")

    // When the user starts typing, treat any prior selection as
    // invalidated until they pick a new one. Freetext mode has no
    // hidden companion to clear — the visible input itself is the
    // form field, so typing IS the new value.
    this.onInput = () => {
      if (freetext) return
      showWarning(false)
      if (hidden && hidden.value) {
        hidden.value = ""
        hidden.dispatchEvent(new Event("input", {bubbles: true}))
      }
    }
    this.el.addEventListener("input", this.onInput)

    // Server-driven reset: allows LiveViews to clear a specific picker
    // (by wrapper id) after a successful batch action, so users can
    // record multiple entries in sequence without stale state.
    this.handleEvent("ac:reset", ({id}) => {
      const wrapperId = hook.el.id.replace(/-input$/, "")
      if (id !== wrapperId) return
      hook.el.value = ""
      showWarning(false)
      if (freetext) {
        hook.el.dispatchEvent(new Event("input", {bubbles: true}))
      } else if (hidden) {
        hidden.value = ""
        hidden.dispatchEvent(new Event("input", {bubbles: true}))
      }
    })

    const listPos = dropUp ? "bottom-full mb-1" : "top-full mt-1"
    const rowPad = touch ? "px-3 py-3" : "px-3 py-1.5"

    this.ac = new autoComplete({
      selector: () => this.el,
      wrapper: false,
      data: {src: items, keys: ["label"], cache: true},
      threshold: 0,
      debounce: 50,
      searchEngine: "strict",
      resultsList: {
        destination: containerFn,
        position: "beforeend",
        maxResults: 20,
        tabSelect: true,
        class:
          `ac-results absolute ${listPos} left-0 z-50 w-full max-h-60 overflow-y-auto rounded border border-base-300 bg-base-100 shadow-lg text-sm divide-y divide-base-200`,
        noResults: (list, _query) => {
          if (!emptyText) return
          const msg = document.createElement("li")
          msg.setAttribute("role", "presentation")
          msg.className =
            "px-3 py-1.5 text-sm text-base-content/60 italic cursor-default select-none"
          msg.textContent = emptyText
          list.appendChild(msg)
        }
      },
      resultItem: {
        class: `ac-result ${rowPad} cursor-pointer hover:bg-base-200`,
        highlight: true,
        selected: "bg-base-200"
      },
      events: {
        input: {
          // Show the full list as soon as the field gets focus — users
          // shouldn't have to type to discover what's available.
          focus: () => {
            showWarning(false)
            hook.ac.start()
          },
          selection: (event) => {
            // autoComplete.js nests the picked record under
            // `selection.value` as `{id, label}` (see vendor feedback()).
            const item = event.detail.selection.value
            if (!item || (item.id == null && !item.label)) return
            // Freetext mode: the visible input IS the form field, so we
            // write the item's `id` (e.g. raw batch tag) into it. Hidden
            // mode: visible shows the rich label, hidden carries the id.
            if (freetext) {
              hook.el.value = item.id
              hook.el.dispatchEvent(new Event("input", {bubbles: true}))
            } else {
              hook.el.value = item.label
              showWarning(false)
              if (hidden) {
                hidden.value = item.id
                // Let the form's phx-change handler run.
                hidden.dispatchEvent(new Event("input", {bubbles: true}))
              }
            }
          },
          // If the user leaves the field with text that uniquely
          // identifies one item (exact label match, or a substring that
          // matches only one item), auto-commit that item's id. Prevents
          // typing "Sow-123" and submitting a form with a nil id.
          //
          // Freetext mode skips this entirely — the visible input value
          // is whatever the user typed, and that's accepted as-is.
          blur: () => {
            if (freetext) return
            if (!hidden) return
            if (hidden.value) {
              showWarning(false)
              hook.ac.close()
              return
            }
            const q = hook.el.value.trim().toLowerCase()
            if (!q) {
              showWarning(false)
              return
            }
            const exact = items.filter(i => i.label.toLowerCase() === q)
            const matches =
              exact.length === 1
                ? exact
                : items.filter(i => i.label.toLowerCase().includes(q))
            if (matches.length === 1) {
              hook.el.value = matches[0].label
              hidden.value = matches[0].id
              hidden.dispatchEvent(new Event("input", {bubbles: true}))
              showWarning(false)
              hook.ac.close()
            } else {
              showWarning(true)
            }
          }
        }
      }
    })
  },
  destroyed() {
    if (this.onInput) this.el.removeEventListener("input", this.onInput)
    if (this.ac) {
      this.ac.unInit()
      this.ac = null
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AutoComplete},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Briefly highlight a list row after the user saves a change to it.
// LVs push `phx:flash-row` with the DOM id of the affected row; we
// add the `.flash-row` class (CSS keyframe in app.css) and remove it
// after the animation finishes. Also smooth-scroll the row into view
// when off-screen so the highlight can't be missed.
window.addEventListener("phx:flash-row", (e) => {
  const el = document.getElementById(e.detail.id)
  if (!el) return
  // Force a reflow so re-applying the same class still re-triggers
  // the animation when the user edits the same row twice in a row.
  el.classList.remove("flash-row")
  void el.offsetWidth
  el.classList.add("flash-row")
  // `block: "nearest"` is a no-op when the row is already visible;
  // off-screen rows scroll just enough to bring them into view.
  el.scrollIntoView({behavior: "smooth", block: "nearest"})
  setTimeout(() => el.classList.remove("flash-row"), 4000)
})

// ---- Custom confirm dialog --------------------------------------------
// Replaces the native window.confirm() that phoenix_html fires for
// `data-confirm`, which is unreliable in iOS standalone PWAs. We intercept
// [data-confirm] clicks in the CAPTURE phase (before phoenix_html's and
// LiveView's bubble-phase window listeners), show an HTML <dialog>, and —
// because a modal is async while confirm() is sync — only re-fire the
// original click once the user accepts. On accept we briefly drop the
// `data-confirm` attribute so the re-dispatched click passes straight
// through with no second prompt. Falls back to native confirm if the
// modal isn't on the page.
document.addEventListener(
  "click",
  (e) => {
    const el = e.target.closest && e.target.closest("[data-confirm]")
    if (!el) return

    const dialog = document.getElementById("js-confirm-modal")
    if (!dialog) return // no modal in this layout → leave native confirm intact

    e.preventDefault()
    e.stopImmediatePropagation()

    dialog.querySelector("#js-confirm-message").textContent =
      el.getAttribute("data-confirm")

    const accept = dialog.querySelector("#js-confirm-accept")
    const cancel = dialog.querySelector("#js-confirm-cancel")

    const cleanup = () => {
      accept.removeEventListener("click", onAccept)
      cancel.removeEventListener("click", onCancel)
      dialog.removeEventListener("close", onCancel)
    }
    const onAccept = () => {
      cleanup()
      dialog.close()
      const message = el.getAttribute("data-confirm")
      el.removeAttribute("data-confirm")
      el.click()
      el.setAttribute("data-confirm", message)
    }
    const onCancel = () => {
      cleanup()
      if (dialog.open) dialog.close()
    }

    accept.addEventListener("click", onAccept)
    cancel.addEventListener("click", onCancel)
    dialog.addEventListener("close", onCancel) // backdrop click / Escape = cancel

    dialog.showModal()
  },
  true,
)

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

