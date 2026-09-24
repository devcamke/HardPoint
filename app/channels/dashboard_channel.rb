# Live refreshes of the owner's dashboard. Turbo's stream names are signed, and on top of that
# this channel only streams a shop's dashboard to its own staff who may see its figures.
class DashboardChannel < Turbo::StreamsChannel
  def subscribed
    if (stream_name = verified_stream_name_from_params) && authorized?(stream_name)
      stream_from stream_name
    else
      reject
    end
  end

  private
    def authorized?(stream_name)
      stream_name == "#{current_account.to_gid_param}:dashboard" &&
        Current.set(account: current_account) { current_account.memberships.find_by(user: current_user)&.can_view_reports? }
    end
end
