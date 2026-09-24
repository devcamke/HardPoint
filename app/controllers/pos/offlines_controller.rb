# The offline till: a page the service worker keeps, which sells from the catalogue snapshot on
# the device when the network is down and queues the sales until it's back.
class Pos::OfflinesController < ApplicationController
  include PosSale
  skip_before_action :set_sale

  layout "pos"

  def show
  end
end
