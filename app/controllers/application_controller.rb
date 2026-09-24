class ApplicationController < ActionController::Base
  # Order matters: the account must be resolved before the session is looked up within it.
  include AccountScoped
  include Authentication
  include Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
