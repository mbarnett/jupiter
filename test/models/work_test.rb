require 'test_helper'

class WorkTest < ActiveSupport::TestCase

  test 'there is no default visibility' do
    work = Work.new_cached_remote_object

    assert_nil work.visibility
  end

  test 'unknown visibilities are not valid' do
    work = Work.new_cached_remote_object

    work.unlock_cache_and_load_remote_object do |unlocked_work|
      unlocked_work.visibility = :some_fake_visibility
    end

    assert_not work.valid?
    assert work.errors[:visibility].present?
    assert_includes work.errors[:visibility], 'some_fake_visibility is not a known visibility'
  end

  test 'embargo is a valid visibility for works' do
    assert_includes Work.valid_visibilities, 'embargo'
  end

  test 'embargo_end_date must be present if visibility is embargo' do
    work = Work.new_cached_remote_object
    work.unlock_cache_and_load_remote_object do |unlocked_work|
      unlocked_work.visibility = Work::VISIBILITY_EMBARGO
    end

    assert_not work.valid?
    assert work.errors[:embargo_end_date].present?
    assert_includes work.errors[:embargo_end_date], "can't be blank"
  end

  test 'embargo_end_date must be blank for non-embargo visibilities' do
    work = Work.new_cached_remote_object
    work.unlock_cache_and_load_remote_object do |unlocked_work|
      unlocked_work.visibility = JupiterCore::VISIBILITY_PUBLIC
      unlocked_work.embargo_end_date = '1992-02-01'
    end

    assert_not work.valid?
    assert work.errors[:embargo_end_date].present?
    assert_includes work.errors[:embargo_end_date], 'must be blank'

    refute work.errors[:visibility].present?
  end

  test '#add_to_path assigns paths properly' do
    work = Work.new_cached_remote_object
    community_id = generate_random_string
    collection_id = generate_random_string

    work.unlock_cache_and_load_remote_object do |unlocked_work|
      unlocked_work.add_to_path(community_id, collection_id)
    end

    assert_includes work.member_of_paths, "#{community_id}/#{collection_id}"
  end

  test 'member_of_paths is not a display attribute' do
    assert_not_includes Work.display_attribute_names, :member_of_paths
  end

end
