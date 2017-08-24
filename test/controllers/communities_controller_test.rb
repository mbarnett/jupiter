require 'test_helper'

class CommunitiesControllerTest < ActionDispatch::IntegrationTest

  def before_all
    super
    @community = Community.new_cached_remote_object(title: 'Nice community',
                                                    owner: 1)
    @community.flush_cache_and_perform_remote_write(&:save!)
  end

  def setup
    sign_in_as users(:admin)
  end

  test 'should get index' do
    get communities_url
    assert_response :success
  end

  test 'should get new' do
    get new_community_url
    assert_response :success
  end

  test 'should create community' do
    assert_difference('Community.count') do
      post communities_url, params: { community: { title: 'New community' } }
    end

    assert_redirected_to community_url(Community.last)
  end

  test 'should show community' do
    get community_url(@community)
    assert_response :success
  end

  test 'should get edit' do
    get edit_community_url(@community)
    assert_response :success
  end

  test 'should update community' do
    patch community_url(@community), params: { community: { title: 'Updated community' } }
    assert_redirected_to community_url(@community)
  end

  test 'should destroy community' do
    admin = users(:admin).id
    community = Community.new_cached_remote_object(title: 'Delete me',
                                                   owner: admin).flush_cache_and_perform_remote_write(&:save!)
    assert_difference('Community.count', -1) do
      delete community_url(community)
    end

    assert_redirected_to admin_communities_and_collections_url
  end

end
