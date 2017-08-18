require 'test_helper'

class CollectionTest < ActiveSupport::TestCase

  test 'visibility callback' do
    c = Collection.new_locked_ldp_object(title: 'foo', owner: users(:regular_user).id)
    assert c.valid?
    assert_equal c.visibility, JupiterCore::VISIBILITY_PUBLIC
  end

end
