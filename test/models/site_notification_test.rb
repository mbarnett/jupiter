require 'test_helper'

class SiteNotificationTest < ActiveSupport::TestCase

  test 'cannot create a blank notification' do
    notification = SiteNotification.new

    assert_not notification.valid?
    assert_includes notification.errors[:message], "can't be blank"
  end

  test 'must be associated with a user' do
    notification = SiteNotification.new(message: 'A test message')
    assert_not notification.valid?
    assert_includes notification.errors[:user], "can't be blank"
    assert_includes notification.errors[:user], 'must exist'
  end

  test 'current notifications scope' do
    assert SiteNotification.current.count == 1
    assert_includes SiteNotification.current, site_notifications(:current_notification)
  end

  test 'past notifications scope' do
    assert SiteNotification.past.count == 2
    assert_includes SiteNotification.past, site_notifications(:past_notification)
    assert_includes SiteNotification.past, site_notifications(:another_past_notification)
  end
end
