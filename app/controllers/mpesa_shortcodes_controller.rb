class MpesaShortcodesController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_shortcode, only: %i[ edit update ]

  def index
    @shortcodes = Current.account.mpesa_shortcodes.includes(:branch).order(:name)
  end

  def new
    @shortcode = Current.account.mpesa_shortcodes.new(environment: Mpesa::Shortcode.simulator_allowed? ? "sandbox" : "production")
  end

  def create
    @shortcode = Current.account.mpesa_shortcodes.new(shortcode_params)

    if @shortcode.save
      redirect_to mpesa_shortcodes_path, notice: "#{@shortcode.label} added. Test the connection, then register it for payments made straight to it."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Blank secret fields keep the saved secrets; they're never shown again once saved.
  def update
    if @shortcode.update(shortcode_params.compact_blank.merge(shortcode_params.slice(:branch_id, :till_number, :active)))
      redirect_to mpesa_shortcodes_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_shortcode
      @shortcode = Current.account.mpesa_shortcodes.find(params[:id])
    end

    def shortcode_params
      permitted = params.expect(mpesa_shortcode: %i[ name branch_id environment transaction_type shortcode till_number consumer_key consumer_secret passkey active ])
      permitted[:branch_id] = Current.account.branches.find(permitted[:branch_id]).id if permitted[:branch_id].present?
      permitted
    end
end
