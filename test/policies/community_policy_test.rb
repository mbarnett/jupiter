require 'test_helper'

class CommunityPolicyTest < ActiveSupport::TestCase

  context 'admin user' do
    should 'have proper authorization over communities' do
      current_user = users(:admin)
      community = Community.new_proxied_remote_object

      assert CommunityPolicy.new(current_user, community).index?
      assert CommunityPolicy.new(current_user, community).create?
      assert CommunityPolicy.new(current_user, community).new?
      assert CommunityPolicy.new(current_user, community).show?
      assert CommunityPolicy.new(current_user, community).edit?
      assert CommunityPolicy.new(current_user, community).update?
      assert CommunityPolicy.new(current_user, community).destroy?
    end
  end

  context 'general user' do
    should 'only be able to see index and show of communities' do
      current_user = users(:regular_user)
      community = Community.new_proxied_remote_object

      assert CommunityPolicy.new(current_user, community).index?
      assert CommunityPolicy.new(current_user, community).show?

      refute CommunityPolicy.new(current_user, community).create?
      refute CommunityPolicy.new(current_user, community).new?
      refute CommunityPolicy.new(current_user, community).edit?
      refute CommunityPolicy.new(current_user, community).update?
      refute CommunityPolicy.new(current_user, community).destroy?
    end
  end

  context 'anon user' do
    should 'only be able to see index and show of communities' do
      current_user = nil
      community = Community.new_proxied_remote_object

      assert CommunityPolicy.new(current_user, community).index?
      assert CommunityPolicy.new(current_user, community).show?

      refute CommunityPolicy.new(current_user, community).create?
      refute CommunityPolicy.new(current_user, community).new?
      refute CommunityPolicy.new(current_user, community).edit?
      refute CommunityPolicy.new(current_user, community).update?
      refute CommunityPolicy.new(current_user, community).destroy?
    end
  end

end
