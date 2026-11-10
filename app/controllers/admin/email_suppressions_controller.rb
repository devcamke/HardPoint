class Admin::EmailSuppressionsController < Admin::BaseController
  # The address works again (a typo fixed, a mailbox emptied): HardPoint and SES may write to it.
  def destroy
    suppression = EmailSuppression.find(params[:id])
    suppression.lift!
    redirect_to admin_email_path, notice: "#{suppression.email} will get email again.", status: :see_other
  end
end
