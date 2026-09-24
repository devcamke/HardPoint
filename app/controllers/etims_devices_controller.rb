class EtimsDevicesController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_device, only: %i[ edit update ]

  def index
    @devices = Current.account.etims_devices.includes(:branch).order(:id)
    @counts = Current.account.etims_submissions.group(:status).count
    @branches_without = Current.account.branches.alphabetically.where.not(id: @devices.map(&:branch_id))
  end

  def new
    @device = Current.account.etims_devices.new(branch: Current.account.branches.find_by(id: params[:branch_id]),
      environment: Mpesa::Shortcode.simulator_allowed? ? "sandbox" : "production")
  end

  def create
    @device = Current.account.etims_devices.new(device_params)

    if @device.save
      redirect_to etims_devices_path, notice: "Added. Now set it up with KRA."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @device.update(device_params.except(:branch_id))
      redirect_to etims_devices_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_device
      @device = Current.account.etims_devices.find(params[:id])
    end

    def device_params
      permitted = params.expect(etims_device: %i[ branch_id environment tin bhf_id serial_number default_item_class_code active ])
      permitted[:branch] = Current.account.branches.find(permitted.delete(:branch_id)) if permitted[:branch_id].present?
      permitted
    end
end
