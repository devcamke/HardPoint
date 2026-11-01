# The help centre, on the public site so it can be read before signing up or while signed out.
class HelpController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  layout "marketing"

  def index
    @query = params[:q].to_s.strip
    @articles = HelpArticle.search(@query)
  end

  def show
    @article = HelpArticle.find(params[:id])
  end
end
