module Account::LiveDashboard
  # Asks open dashboards to refresh (debounced, so a busy till doesn't flood them).
  def refresh_dashboard_later
    Turbo::StreamsChannel.broadcast_refresh_later_to(self, :dashboard)
  end
end
