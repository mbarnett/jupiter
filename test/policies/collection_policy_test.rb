require 'test_helper'

class CollectionPolicyTest < ActiveSupport::TestCase

  context 'admin user' do
    should 'have proper authorization over collections' do
      current_user = users(:admin)
      collection = Collection.new_cached_remote_object

      assert CollectionPolicy.new(current_user, collection).index?
      assert CollectionPolicy.new(current_user, collection).create?
      assert CollectionPolicy.new(current_user, collection).new?
      assert CollectionPolicy.new(current_user, collection).show?
      assert CollectionPolicy.new(current_user, collection).edit?
      assert CollectionPolicy.new(current_user, collection).update?
      assert CollectionPolicy.new(current_user, collection).destroy?
    end
  end

  context 'general user' do
    should 'only be able to see index and show of collections' do
      current_user = users(:regular_user)
      collection = Collection.new_cached_remote_object

      assert CollectionPolicy.new(current_user, collection).index?
      assert CollectionPolicy.new(current_user, collection).show?

      refute CollectionPolicy.new(current_user, collection).create?
      refute CollectionPolicy.new(current_user, collection).new?
      refute CollectionPolicy.new(current_user, collection).edit?
      refute CollectionPolicy.new(current_user, collection).update?
      refute CollectionPolicy.new(current_user, collection).destroy?
    end
  end

  context 'anon user' do
    should 'only be able to see index and show of collections' do
      current_user = nil
      collection = Collection.new_cached_remote_object

      assert CollectionPolicy.new(current_user, collection).index?
      assert CollectionPolicy.new(current_user, collection).show?

      refute CollectionPolicy.new(current_user, collection).create?
      refute CollectionPolicy.new(current_user, collection).new?
      refute CollectionPolicy.new(current_user, collection).edit?
      refute CollectionPolicy.new(current_user, collection).update?
      refute CollectionPolicy.new(current_user, collection).destroy?
    end
  end

end
