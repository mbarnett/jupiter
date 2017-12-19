require 'application_system_test_case'

class AdminUsersShowTest < ApplicationSystemTestCase

  should 'not be able to toggle suspended/admin or login as yourself' do
    admin = users(:admin)

    login_user(admin)

    click_link admin.name # opens user dropdown which has the admin link
    click_link I18n.t('application.navbar.links.admin')

    assert_selector 'h1', text: I18n.t('admin.dashboard.index.header')

    click_link I18n.t('admin.users.index.header')
    assert_selector 'h1', text: I18n.t('admin.users.index.header')
    assert_selector 'tbody tr', count: 4
    assert_selector 'tbody tr:first-child th[scope="row"]', text: admin.email

    click_link admin.email

    assert_selector 'h1', text: admin.name

    # shouldn't be any toggle suspend/admin or login as buttons on this page
    refute_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')

    logout_user
  end

  should 'be able to toggle suspended/admin a regular user' do
    admin = users(:admin)
    user = users(:regular_user)

    login_user(admin)

    click_link admin.name # opens user dropdown which has the admin link
    click_link I18n.t('application.navbar.links.admin')

    assert_selector 'h1', text: I18n.t('admin.dashboard.index.header')

    click_link I18n.t('admin.users.index.header')
    assert_selector 'h1', text: I18n.t('admin.users.index.header')
    assert_selector 'tbody tr', count: 4
    assert_selector 'tbody tr:first-child th[scope="row"]', text: admin.email

    click_link user.email

    assert_selector 'h1', text: user.name

    assert_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')

    accept_confirm do
      click_link I18n.t('admin.users.show.grant_admin_link_text')
    end

    assert_text I18n.t('admin.users.show.grant_admin_flash', user: user.name)
    assert_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')

    accept_confirm do
      click_link I18n.t('admin.users.show.revoke_admin_link_text')
    end

    assert_text I18n.t('admin.users.show.revoke_admin_flash', user: user.name)
    assert_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')

    accept_confirm do
      click_link I18n.t('admin.users.show.suspend_link_text')
    end

    assert_text I18n.t('admin.users.show.suspend_flash', user: user.name)
    assert_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')

    accept_confirm do
      click_link I18n.t('admin.users.show.unsuspend_link_text')
    end

    assert_text I18n.t('admin.users.show.unsuspend_flash', user: user.name)
    assert_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')

    logout_user
  end

  should 'be able to login as a regular user' do
    admin = users(:admin)
    user = users(:regular_user)

    login_user(admin)

    click_link admin.name # opens user dropdown which has the admin link
    click_link I18n.t('application.navbar.links.admin')

    assert_selector 'h1', text: I18n.t('admin.dashboard.index.header')

    click_link I18n.t('admin.users.index.header')
    assert_selector 'h1', text: I18n.t('admin.users.index.header')
    assert_selector 'tbody tr', count: 4
    assert_selector 'tbody tr:first-child th[scope="row"]', text: admin.email

    click_link user.email

    assert_selector 'h1', text: user.name

    assert_selector :link, text: I18n.t('admin.users.show.suspend_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.grant_admin_link_text')
    assert_selector :link, text: I18n.t('admin.users.show.login_as_user_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.unsuspend_link_text')
    refute_selector :link, text: I18n.t('admin.users.show.revoke_admin_link_text')

    accept_confirm do
      click_link I18n.t('admin.users.show.login_as_user_link_text')
    end

    # we signed in as user and have been redirected to homepage
    assert_text I18n.t('admin.users.show.login_as_user_flash', user: user.name)
    assert_text user.name
    assert_selector 'h1', text: I18n.t('welcome.index.header')

    # we log out as user and get redirected back to admin user show page
    click_link user.name # opens user dropdown which has the logout as user link
    click_link I18n.t('application.navbar.links.logout_as_user')
    assert_text I18n.t('sessions.logout_as_user.flash', original_user: user.name)
    assert_selector 'h1', text: user.name

    logout_user
  end

  should 'be able to view items owned by user' do
    # Note: searching and faceting is covered more extensively in tests elsewhere
    user = User.find_by(email: 'john_snow@example.com')
    admin = users(:admin)

    community = Community.new_locked_ldp_object(title: 'Fancy Community', owner: 1)
                         .unlock_and_fetch_ldp_object(&:save!)
    collection = Collection.new_locked_ldp_object(community_id: community.id,
                                                  title: 'Fancy Collection', owner: 1)
                           .unlock_and_fetch_ldp_object(&:save!)

    # Two items owned by regular user
    ['Fancy', 'Nice'].each do |adjective|
      Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PUBLIC,
                                 owner: user.id, title: "#{adjective} Item",
                                 languages: [CONTROLLED_VOCABULARIES[:language].english],
                                 license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international,
                                 item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                 publication_status: CONTROLLED_VOCABULARIES[:publication_status].published)
          .unlock_and_fetch_ldp_object do |uo|
        uo.add_to_path(community.id, collection.id)
        uo.save!
      end
    end
    # One item owned by admin
    Item.new_locked_ldp_object(visibility: JupiterCore::VISIBILITY_PUBLIC,
                               owner: admin.id, title: 'Admin Item',
                               languages: [CONTROLLED_VOCABULARIES[:language].english],
                               license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international,
                               item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                               publication_status: CONTROLLED_VOCABULARIES[:publication_status].published)
        .unlock_and_fetch_ldp_object do |uo|
      uo.add_to_path(community.id, collection.id)
      uo.save!
    end

    login_user(admin)

    # Would like to do `visit admin_user_path(user)`, but seems broken (?)
    click_link admin.name
    click_link I18n.t('application.navbar.links.admin')
    click_link I18n.t('admin.users.index.header')
    click_link user.email

    # Should be able to find the two items this guy owns
    assert_selector 'div.jupiter-results-list li.list-group-item', count: 2
    assert_selector 'div.jupiter-results-list li.list-group-item .media-body a', text: 'Fancy Item', count: 1
    assert_selector 'div.jupiter-results-list li.list-group-item .media-body a', text: 'Nice Item', count: 1

    # Should not be able to find the item owned by admin
    refute_selector 'div.jupiter-results-list li.list-group-item .media-body a', text: 'Admin Item'

    # Search items
    fill_in name: 'query', with: 'Fancy'
    click_button 'Search Items'
    assert_selector 'div.jupiter-results-list li.list-group-item', count: 1
    assert_selector 'div.jupiter-results-list li.list-group-item .media-body a', text: 'Fancy Item', count: 1
    refute_selector 'div.jupiter-results-list li.list-group-item .media-body a', text: 'Nice Item'

    logout_user
  end

end
