# Sets the control unit up with KRA, which returns its communication key.
class EtimsDevices::InitializationsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    device = Current.account.etims_devices.find(params[:etims_device_id])
    device.initialize_with_kra
    redirect_to etims_devices_path, notice: "#{device.name} is set up with KRA (#{device.sdc_id}). Sales there are now sent to eTIMS.", status: :see_other
  rescue Etims::Client::Refused, JsonHttp::Unreachable => error
    redirect_to etims_devices_path, alert: "KRA didn't set it up: #{error.message}", status: :see_other
  end
end
