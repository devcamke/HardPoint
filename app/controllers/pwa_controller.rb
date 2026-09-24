# The installable till: its web app manifest and the service worker that keeps the offline till.
class PwaController < ActionController::Base
  skip_forgery_protection

  def manifest
    render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json"
  end

  def service_worker
    response.headers["Cache-Control"] = "no-cache"
    render template: "pwa/service-worker", formats: :js, content_type: "text/javascript"
  end
end
