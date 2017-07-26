class ApplicationController < ActionController::Base

  protect_from_forgery with: :exception
  
   helper_method :current_site_notifications

  protected

  # Returns the current logged-in user (if any).
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  # Let views be able to access current_user
  helper_method :current_user

  # Signs in the given user.
  def sign_in(user)
    @current_user = user
    session[:user_id] = user.try(:id)
  end

  # Logs out the current user.
  def log_off_user
    session[:user_id] = nil
    @current_user = nil
  end

  def current_site_notifications
    SiteNotification.current
  end

  # TODO: remove shim
  def current_user
    User.first
  end

end
