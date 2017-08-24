require 'test_helper'

class CommunityTest < ActiveSupport::TestCase

  test 'visibility callback' do
    c = Community.new_proxied_remote_object(title: 'foo', owner: users(:admin).id)
    assert c.valid?
    assert_equal c.visibility, JupiterCore::VISIBILITY_PUBLIC
  end

end
