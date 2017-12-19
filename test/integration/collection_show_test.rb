require 'test_helper'

# TODO: This test would be better as an System Acceptance test instead?
class CollectionShowTest < ActionDispatch::IntegrationTest

  # TODO: add tests involving non-public items

  def before_all
    super

    # TODO: setup proper fixtures for LockedLdpObjects

    # A community with a collection
    @community = Community.new_locked_ldp_object(title: 'Two collection community', owner: 1)
                          .unlock_and_fetch_ldp_object(&:save!)
    @collection = Collection.new_locked_ldp_object(community_id: @community.id, title: 'Nice collection', owner: 1)
                            .unlock_and_fetch_ldp_object(&:save!)
    @items = ['Fancy', 'Nice'].map do |adjective|
      Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PUBLIC,
                                 owner: 1,
                                 languages: [CONTROLLED_VOCABULARIES[:language].english],
                                 license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international,
                                 item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                 publication_status: CONTROLLED_VOCABULARIES[:publication_status].published,
                                 title: "#{adjective} Item").unlock_and_fetch_ldp_object do |uo|
        uo.add_to_path(@community.id, @collection.id)
        uo.save!
      end
    end
  end

  test 'visiting the show page for a collection as an admin' do
    admin = users(:admin)
    sign_in_as admin
    get community_collection_url(@community, @collection)

    # Breadcrumb
    assert_select 'ol.breadcrumb', count: 1
    assert_select 'li.breadcrumb-item', count: 2
    assert_select 'li.breadcrumb-item a', text: @community.title
    assert_select 'li.breadcrumb-item a', text: @collection.title, count: 0
    assert_select 'li.breadcrumb-item.active', text: @collection.title

    # Edit collection link
    assert_select "a[href='#{edit_admin_community_collection_path(@community, @collection)}']", text: 'Edit'

    # Delete collection link
    delete = css_select "a[href='#{admin_community_collection_path(@community, @collection)}']"
    assert_equal delete.count, 1
    assert_equal delete.first.attributes['data-method'].to_s, 'delete'

    # Items are shown
    assert_select '.jupiter-results ul.list-group .list-group-item', count: 2

    # Links to items
    @items.each do |item|
      item_links = css_select ".jupiter-results ul.list-group .list-group-item a[href='#{item_path(item)}']"

      # Thumbnail, text link, and delete link
      assert_equal item_links.count, 3
      # Thumbnail link to item
      assert_includes item_links.first.inner_html, 'img-thumbnail'
      # Text link to item
      assert_equal item_links[1].text, item.title
      # Link to delete item
      assert_match 'Delete', item_links.last.text
      assert_equal item_links.last.attributes['data-method'].to_s, 'delete'

      # Link to edit item
      assert_select "ul.list-group .list-group-item a[href='#{edit_item_path(item)}']", text: 'Edit'
    end
  end

  test 'visiting the show page for a collection as a regular user' do
    user = users(:regular_user)
    sign_in_as user
    get community_collection_url(@community, @collection)

    # Breadcrumb
    assert_select 'ol.breadcrumb', count: 1
    assert_select 'li.breadcrumb-item', count: 2
    assert_select 'li.breadcrumb-item a', text: @community.title
    assert_select 'li.breadcrumb-item a', text: @collection.title, count: 0
    assert_select 'li.breadcrumb-item.active', text: @collection.title

    # No edit community link
    assert_select "a[href='#{edit_admin_community_collection_path(@community, @collection)}']",
                  count: 0
    # No delete community link
    assert_select "a[href='#{admin_community_collection_path(@community, @collection)}']",
                  count: 0

    # Items are shown
    assert_select '.jupiter-results ul.list-group .list-group-item', count: 2

    # Links to items
    @items.each do |item|
      item_links = css_select ".jupiter-results ul.list-group .list-group-item a[href='#{item_path(item)}']"
      # Only thumbnail and text link expected
      assert_equal item_links.count, 2
      # Thumbnail link to item
      assert_includes item_links.first.inner_html, 'img-thumbnail'
      # Link to item
      assert_equal item_links.last.text, item.title
      # No link to delete item
      refute_equal item_links.first.attributes['data-method'].to_s, 'delete'
      refute_equal item_links.last.attributes['data-method'].to_s, 'delete'
      # No link to edit item
      assert_select "ul.list-group .list-group-item a[href='#{edit_item_path(item)}']", count: 0
    end
  end

  test 'searching within the collection as a regular user' do
    # TODO: should probably hook this up to a system test that submits the form
    user = users(:regular_user)
    sign_in_as user
    get community_collection_url(@community, @collection, query: 'Fancy')

    # Only 'Fancy' items are shown
    assert_select '.jupiter-results ul.list-group .list-group-item', count: 1
    assert_select '.jupiter-results ul.list-group .list-group-item a', text: 'Fancy Item', count: 1
    assert_select '.jupiter-results ul.list-group .list-group-item a', text: 'Nice Item', count: 0
  end

end
