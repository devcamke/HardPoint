# The installable till (and the stock app for phones): their web app manifests and the service worker that keeps the offline till.
class PwaController < ActionController::Base
  skip_forgery_protection

  def manifest
    render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json"
  end

  # The stock app for phones: counting, receiving and looking things up with the camera.
  def stock_manifest
    render template: "pwa/stock_manifest", formats: :json, content_type: "application/manifest+json"
  end

  def service_worker
    response.headers["Cache-Control"] = "no-cache"
    render template: "pwa/service-worker", formats: :js, content_type: "text/javascript"
  end
end
