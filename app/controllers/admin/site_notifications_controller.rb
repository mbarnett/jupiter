class Admin::SiteNotificationsController < Admin::AdminController

  helper_method :current_notifications, :past_notifications

  def new
    @new_notification = SiteNotification.new
  end

  def create
    @new_notification = SiteNotification.new(notification_params)
    @new_notification.user = current_user

    if @new_notification.save
      redirect_to new_admin_site_notification_path
    else
      render action: 'new'
    end
  end

  def destroy
    notification = SiteNotification.find(params[:id])
    notification.removed_at = DateTime.now
    notification.save!
    redirect_to new_admin_site_notification_path
  end

  protected

  def current_notifications
    SiteNotification.current
  end

  def past_notifications
    SiteNotification.past
  end

  def notification_params
    params[:site_notification].permit(:message)
  end

end
