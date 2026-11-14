# Pin npm packages by running ./bin/importmap

pin "application"
pin "scrollable_regions"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/offline", under: "offline"
# Mozilla's pdf.js 4.10.38 (Apache-2.0), vendored (as .js, so it is served as JavaScript) and checked against the npm package: draws documents' PDFs as
# pictures to share. Loaded only when someone shares a picture; its worker is served from vendor/javascript too.
pin "pdfjs-dist", to: "pdfjs.min.js", preload: false # @4.10.38
# Reading a weighing scale on the till's serial port (Web Serial); loaded by the till's Weigh button.
pin_all_from "app/javascript/scale", under: "scale", preload: false
