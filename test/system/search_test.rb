require 'application_system_test_case'

class SearchTest < ApplicationSystemTestCase

  def before_all
    super
    @community = Community.new_locked_ldp_object(title: 'Fancy Community', owner: 1)
                          .unlock_and_fetch_ldp_object(&:save!)
    @collections = 2.times.map do |i|
      Collection.new_locked_ldp_object(community_id: @community.id,
                                       title: "Fancy Collection #{i}", owner: 1)
                .unlock_and_fetch_ldp_object(&:save!)
    end

    # Half items have 'Fancy' in title, others have 'Nice', distributed between the two collections
    @items = 10.times.map do |i|
      Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PUBLIC,
                                 owner: 1, title: "#{['Fancy', 'Nice'][i % 2]} Item #{i}",
                                 languages: [CONTROLLED_VOCABULARIES[:language].english],
                                 item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                 publication_status: CONTROLLED_VOCABULARIES[:publication_status].published,
                                 license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)
          .unlock_and_fetch_ldp_object do |uo|
        uo.add_to_path(@community.id, @collections[i / 5].id)
        uo.save!
      end
    end
    # 10 more items. these are private (some 'Fancy' some 'Nice')
    @items += 10.times.map do |i|
      Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PRIVATE,
                                 owner: 1, title: "#{['Fancy', 'Nice'][i % 2]} Private Item #{i + 10}",
                                 languages: [CONTROLLED_VOCABULARIES[:language].english],
                                 item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                 publication_status: CONTROLLED_VOCABULARIES[:publication_status].published,
                                 license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)
          .unlock_and_fetch_ldp_object do |uo|
        uo.add_to_path(@community.id, @collections[i / 5].id)
        uo.save!
      end
    end

    # Create extra items/collections/communities to test 'show more'
    10.times do |i|
      community = Community.new_locked_ldp_object(title: "Extra Community #{i}", owner: 1)
                           .unlock_and_fetch_ldp_object(&:save!)
      collection = Collection.new_locked_ldp_object(community_id: community.id,
                                                    title: "Extra Collection #{i}", owner: 1)
                             .unlock_and_fetch_ldp_object(&:save!)
      Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PUBLIC,
                                 owner: 1, title: "Extra Item #{i}",
                                 languages: [CONTROLLED_VOCABULARIES[:language].english],
                                 item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                 publication_status: CONTROLLED_VOCABULARIES[:publication_status].published,
                                 license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)
          .unlock_and_fetch_ldp_object do |uo|
        uo.add_to_path(community.id, collection.id)
        uo.save!
      end
    end
  end

  context 'Searching as non-logged in user' do
    should 'be able to filter the public items' do
      visit root_path
      fill_in name: 'search', with: 'Fancy'
      click_button 'Search'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy')
      # Tabs
      assert_selector 'a.nav-link.active', text: 'Items (5)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'

      # Facets and counts
      assert_selector 'div.card-header', text: 'Visibility'
      assert_selector 'li div', text: /Public.*5/
      # Should not be a facet for 'private'
      assert_selector 'li div', text: /private/, count: 0
      # TODO: The 'Member of paths' text will likely change
      assert_selector 'div.card-header', text: 'Collections'
      assert_selector 'li div', text: /Fancy Community.*5/
      assert_selector 'li div', text: /Fancy Collection 0.*3/
      assert_selector 'li div', text: /Fancy Collection 1.*2/

      # Exactly 5 items shown
      assert_selector 'div.jupiter-results-list li.list-group-item', count: 5
      assert_selector 'a', text: 'Fancy Item 0'
      assert_selector 'a', text: 'Fancy Item 2'
      assert_selector 'a', text: 'Fancy Item 4'
      assert_selector 'a', text: 'Fancy Item 6'
      assert_selector 'a', text: 'Fancy Item 8'

      # Click on facet
      # A checkbox for the facet should be unchecked, and link should turn on face
      path = "#{@community.id}/#{@collections[1].id}"
      facet_path = search_path(search: 'Fancy', facets: { member_of_paths_dpsim: path })

      facets = find('div.jupiter-facets')
      facet = facets.find_link('a', text: 'Fancy Collection 1', href: facet_path)
      checkbox = facet.find 'input'
      refute checkbox.checked?

      click_link 'Fancy Collection 1'
      assert_equal URI.parse(current_url).request_uri, facet_path

      # Tab counts should only change for this tab
      assert_selector 'a.nav-link.active', text: 'Items (2)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'

      # Some facets are now gone, some with changed counts
      assert_selector 'div.card-header', text: 'Visibility'
      assert_selector 'li div', text: /Public.*2/
      assert_selector 'div.card-header', text: 'Collections'
      assert_selector 'li div', text: /Fancy Community.*2/
      assert_selector 'li div', text: /Fancy Collection 0/, count: 0
      assert_selector 'li div', text: /Fancy Collection 1.*2/

      # A checkbox for the selected facet should be checked, and link should turn off facet
      facets = find('div.jupiter-facets')
      facet = facets.find_link('a', text: 'Fancy Collection 1', href: search_path(search: 'Fancy'))
      checkbox = facet.find 'input'
      assert checkbox.checked?

      # 2 items shown, 3 not shown
      assert_selector 'div.jupiter-results-list li.list-group-item', count: 2
      assert_selector 'a', text: 'Fancy Item 6'
      assert_selector 'a', text: 'Fancy Item 8'
      assert_selector 'a', text: 'Fancy Item 0', count: 0
      assert_selector 'a', text: 'Fancy Item 2', count: 0
      assert_selector 'a', text: 'Fancy Item 4', count: 0

      # A badge should be displayed for the enabled facet as a link that turns off facet
      badges = find('div.jupiter-facet-badges')
      badge = badges.find_link('a', text: 'Fancy Collection 1', href: search_path(search: 'Fancy'))
      badge.assert_selector 'span.badge', text: 'Fancy Collection 1'
    end

    should 'be able to view community/collection hits via tabs' do
      visit root_path
      fill_in name: 'search', with: 'Fancy'
      click_button 'Search'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy')

      # Tabs
      assert_selector 'a.nav-link.active', text: 'Items (5)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'

      # No community/collection results initially shown
      assert_selector 'div.jupiter-results-list a', text: 'Item', count: 10
      assert_selector 'div.jupiter-results-list a', text: 'Community', count: 0
      assert_selector 'div.jupiter-results-list a', text: 'Collection', count: 0

      # Visit community tab
      click_link 'Communities (1)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy', tab: 'community')
      assert_selector 'a.nav-link', text: 'Items (5)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link.active', text: 'Communities (1)'
      # Only community hits shown
      assert_selector 'div.jupiter-results-list a', text: 'Item', count: 0
      assert_selector 'div.jupiter-results-list a', text: 'Community', count: 1
      assert_selector 'div.jupiter-results-list a', text: 'Collection', count: 0

      # Visit collection tab
      click_link 'Collections (2)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy', tab: 'collection')
      assert_selector 'a.nav-link', text: 'Items (5)'
      assert_selector 'a.nav-link.active', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'
      # Only collection hits shown
      assert_selector 'div.jupiter-results-list a', text: 'Item', count: 0
      assert_selector 'div.jupiter-results-list a', text: 'Community', count: 0
      assert_selector 'div.jupiter-results-list a', text: 'Collection', count: 2
    end

    should 'only show some facet results by default, with a "show more" button' do
      visit root_path
      fill_in name: 'search', with: 'Extra'
      click_button 'Search'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Extra')

      # Facets and counts. 20 should match, expect only 6 to be shown
      assert_selector 'div.card-header', text: 'Collections'
      # Note: collection facets also include community name
      assert_selector 'li div a', text: /Extra Community/, count: 6

      # Should be a 'Show more' button to see the rest
      assert_selector 'a', text: 'Show 14 more', count: 1

      click_link 'Show 14 more'

      # Now 20 collections/communities should be shown
      assert_selector 'li div a', text: /Extra Community/, count: 20

      # Should be a 'Hide' button now
      assert_selector 'a', text: 'Hide last 14', count: 1

      click_link 'Hide last 14'

      # Again, only 6 collections/communities should be shown
      assert_selector 'li div a', text: /Extra Community/, count: 6
    end

    should 'be able to sort results' do
      visit root_path
      fill_in name: 'search', with: 'Fancy'
      click_button 'Search'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy')

      # Default sort is by title
      assert_match(/Fancy Item 0.*Fancy Item 2.*Fancy Item 4.*Fancy Item 6.*Fancy Item 8/, page.text)

      # Sort sort links
      click_button 'Sort by'
      assert_selector 'a', text: 'Title (A-Z)'
      assert_selector 'a', text: 'Title (Z-A)'
      assert_selector 'a', text: 'Date (newest first)'
      assert_selector 'a', text: 'Date (oldest first)'

      # Reverse sort
      click_link 'Title (Z-A)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy', sort: 'title', direction: 'desc')
      assert_selector 'button', text: 'Title (Z-A)'
      assert_match(/Fancy Item 8.*Fancy Item 6.*Fancy Item 4.*Fancy Item 2.*Fancy Item 0/, page.text)

      # Sort the other way again
      click_button 'Title (Z-A)'
      click_link 'Title (A-Z)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy', sort: 'title', direction: 'asc')
      assert_selector 'button', text: 'Title (A-Z)'
      assert_match(/Fancy Item 0.*Fancy Item 2.*Fancy Item 4.*Fancy Item 6.*Fancy Item 8/, page.text)

      # Sort with newest first
      click_button 'Title (A-Z)'
      click_link 'Date (newest first)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy',
                                                                   sort: 'record_created_at', direction: 'desc')
      assert_selector 'button', text: 'Date (newest first)'
      assert_match(/Fancy Item 8.*Fancy Item 6.*Fancy Item 4.*Fancy Item 2.*Fancy Item 0/, page.text)

      # Sort with oldest first
      click_button 'Date (newest first)'
      click_link 'Date (oldest first)'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy',
                                                                   sort: 'record_created_at', direction: 'asc')
      assert_selector 'button', text: 'Date (oldest first)'
      assert_match(/Fancy Item 0.*Fancy Item 2.*Fancy Item 4.*Fancy Item 6.*Fancy Item 8/, page.text)
    end
  end

  context 'Searching as admin user' do
    should 'be able to filter the public and private items' do
      admin = users(:admin)
      login_user(admin)

      # Search box should be on any page we happen to be on
      fill_in name: 'search', with: 'Fancy'
      click_button 'Search'
      assert_equal URI.parse(current_url).request_uri, search_path(search: 'Fancy')

      # Tabs
      assert_selector 'a.nav-link.active', text: 'Items (10)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'

      # Facets and counts
      assert_selector 'div.card-header', text: 'Visibility'
      assert_selector 'li div', text: /Public.*5/
      # Should be a facet for 'private'
      assert_selector 'li div', text: /Private.*5/
      # TODO: The 'Member of paths' text will likely change
      assert_selector 'div.card-header', text: 'Collections'
      assert_selector 'li div', text: /Fancy Community.*10/
      assert_selector 'li div', text: /Fancy Collection 0.*6/
      assert_selector 'li div', text: /Fancy Collection 1.*4/

      # Exactly 10 items shown
      assert_selector 'div.jupiter-results-list li.list-group-item', count: 10
      assert_selector 'a', text: 'Fancy Item 0'
      assert_selector 'a', text: 'Fancy Item 2'
      assert_selector 'a', text: 'Fancy Item 4'
      assert_selector 'a', text: 'Fancy Item 6'
      assert_selector 'a', text: 'Fancy Item 8'
      assert_selector 'a', text: 'Fancy Private Item 10'
      assert_selector 'a', text: 'Fancy Private Item 12'
      assert_selector 'a', text: 'Fancy Private Item 14'
      assert_selector 'a', text: 'Fancy Private Item 16'
      assert_selector 'a', text: 'Fancy Private Item 18'

      # Click on facet
      # A checkbox for the facet should be unchecked, and link should turn on face
      path = "#{@community.id}/#{@collections[1].id}"
      facet_path = search_path(search: 'Fancy', facets: { member_of_paths_dpsim: path })

      facets = find('div.jupiter-facets')
      facet = facets.find_link('a', text: 'Fancy Collection 1', href: facet_path)
      checkbox = facet.find 'input'
      refute checkbox.checked?

      click_link 'Fancy Collection 1'
      assert_equal URI.parse(current_url).request_uri, facet_path

      # Tab counts should only change for this tab
      assert_selector 'a.nav-link.active', text: 'Items (4)'
      assert_selector 'a.nav-link', text: 'Collections (2)'
      assert_selector 'a.nav-link', text: 'Communities (1)'

      # Some facets are now gone, some with changed counts
      assert_selector 'div.card-header', text: 'Visibility'
      assert_selector 'li div', text: /Public.*2/
      assert_selector 'div.card-header', text: 'Collections'
      assert_selector 'li div', text: /Fancy Community.*4/
      assert_selector 'li div', text: /Fancy Collection 0/, count: 0
      assert_selector 'li div', text: /Fancy Collection 1.*4/

      # A checkbox for the selected facet should be checked, and link should turn off facet
      facets = find('div.jupiter-facets')
      facet = facets.find_link('a', text: 'Fancy Collection 1', href: search_path(search: 'Fancy'))
      checkbox = facet.find 'input'
      assert checkbox.checked?

      # 2 items shown, 3 not shown
      assert_selector 'a', text: 'Fancy Item 6'
      assert_selector 'a', text: 'Fancy Item 8'
      assert_selector 'a', text: 'Fancy Item 0', count: 0
      assert_selector 'a', text: 'Fancy Item 2', count: 0
      assert_selector 'a', text: 'Fancy Item 4', count: 0

      # A badge should be displayed for the enabled facet as a link that turns off facet
      badges = find('div.jupiter-facet-badges')
      badge = badges.find_link('a', text: 'Fancy Collection 1', href: search_path(search: 'Fancy'))
      badge.assert_selector 'span.badge', text: 'Fancy Collection 1'
    end
  end

end
