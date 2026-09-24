class Admin::AnnouncementsController < Admin::BaseController
  before_action :set_announcement, only: %i[ edit update destroy ]

  def index
    @announcements = Announcement.chronologically
  end

  def new
    @announcement = Announcement.new(starts_at: Time.current.beginning_of_hour, level: "info")
  end

  def create
    @announcement = Announcement.new(announcement_params)
    if @announcement.save
      redirect_to admin_announcements_path, notice: "Announcement saved.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @announcement.update(announcement_params)
      redirect_to admin_announcements_path, notice: "Announcement saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @announcement.destroy!
    redirect_to admin_announcements_path, notice: "Announcement removed.", status: :see_other
  end

  private
    def set_announcement
      @announcement = Announcement.find(params[:id])
    end

    def announcement_params
      params.expect(announcement: %i[ title body level starts_at ends_at ])
    end
end
