require 'test_helper'

class SiteNotificationTest < ActiveSupport::TestCase

  context 'associations' do
    should belong_to(:user)
  end

  context 'validations' do
    should validate_presence_of(:message)
    should validate_presence_of(:user)
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
