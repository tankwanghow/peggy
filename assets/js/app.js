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
          "ac-results absolute top-full left-0 z-50 mt-1 w-full max-h-48 overflow-y-auto rounded border border-base-300 bg-base-100 shadow-lg text-sm",
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
        class: "ac-result px-3 py-1.5 cursor-pointer hover:bg-base-200",
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
            const sel = event.detail.selection.value
            // Freetext mode: the visible input IS the form field, so we
            // write the item's `id` (e.g. raw batch tag) into it. Hidden
            // mode: visible shows the rich label, hidden carries the id.
            if (freetext) {
              hook.el.value = sel.id
              hook.el.dispatchEvent(new Event("input", {bubbles: true}))
            } else {
              hook.el.value = sel.label
              showWarning(false)
              if (hidden) {
                hidden.value = sel.id
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

