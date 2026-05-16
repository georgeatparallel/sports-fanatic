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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

// Scroll chat to show latest user message, but don't force-scroll during agent responses
Hooks.ScrollBottom = {
  mounted() {
    this.lastChildCount = this.el.children.length
    this.observer = new MutationObserver(() => {
      const newCount = this.el.children.length
      // Only auto-scroll when a user message is added (blue bubble)
      // Don't scroll during agent response streaming — let user read at their pace
      const lastChild = this.el.lastElementChild
      if (lastChild && newCount > this.lastChildCount) {
        const isUserMsg = lastChild.querySelector('.bg-blue-500')
        const isProgress = lastChild.querySelector('.animate-spin')
        if (isUserMsg || isProgress) {
          this.el.scrollTop = this.el.scrollHeight
        }
      }
      this.lastChildCount = newCount
    })
    this.observer.observe(this.el, { childList: true })
  },
  destroyed() {
    if (this.observer) this.observer.disconnect()
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})

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

