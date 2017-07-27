require 'test_helper'

class Admin::SiteNotificationsControllerTest < ActionDispatch::IntegrationTest

  test 'new' do
    sign_in_as users(:admin)

    get new_admin_site_notification_url
    assert_response :success
  end

  test 'create' do
    sign_in_as users(:admin)
#    sleep 5

    assert_difference('SiteNotification.current.count') do
      post admin_site_notifications_url, params: { site_notification: { message: 'Some message' } }
    end
    assert_redirected_to new_admin_site_notification_url
  end

  test 'destroy' do
    sign_in_as users(:admin)

    assert_difference('SiteNotification.past.count') do
      delete admin_site_notification_url(site_notifications(:current_notification))
    end
    assert_redirected_to new_admin_site_notification_url
    assert_not_includes SiteNotification.current, site_notifications(:current_notification)
  end

end
