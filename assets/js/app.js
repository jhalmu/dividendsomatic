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
import {hooks as colocatedHooks} from "phoenix-colocated/dividendsomatic"
import topbar from "../vendor/topbar"
import ApexChartHook from "./hooks/apex_chart_hook"

// Custom hooks
const Hooks = {
  KeyboardNav: {
    mounted() {
      this.handleKeydown = (e) => {
        // Skip when focus is in an input field
        if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return

        if (e.shiftKey && e.key === "ArrowLeft") {
          this.pushEvent("navigate", {direction: "back_week"})
        } else if (e.shiftKey && e.key === "ArrowRight") {
          this.pushEvent("navigate", {direction: "forward_week"})
        } else if (e.key === "ArrowLeft") {
          this.pushEvent("navigate", {direction: "prev"})
        } else if (e.key === "ArrowRight") {
          this.pushEvent("navigate", {direction: "next"})
        }
      }
      window.addEventListener("keydown", this.handleKeydown)
    },
    destroyed() {
      window.removeEventListener("keydown", this.handleKeydown)
    }
  },
  ApexChartHook: ApexChartHook,
  DatePickerSubmit: {
    mounted() {
      this.el.addEventListener("change", () => {
        this.el.closest("form").dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
      })
    }
  },
  LoadingTimer: {
    mounted() {
      this.start = Date.now()
      this.timer = setInterval(() => {
        const s = Math.floor((Date.now() - this.start) / 1000)
        this.el.textContent = `Loading portfolio data... ${s}s`
      }, 1000)
    },
    destroyed() {
      clearInterval(this.timer)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#38BDF8"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// View Transitions API for smooth page navigations
if (document.startViewTransition) {
  window.addEventListener("phx:page-loading-start", (info) => {
    if (info.detail?.kind === "redirect" || info.detail?.kind === "initial") {
      document.startViewTransition()
    }
  })
}

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
    window.addEventListener("keyup", e => keyDown = null)
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
