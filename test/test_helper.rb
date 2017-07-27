require 'simplecov'
SimpleCov.start 'rails' unless ENV['NO_COVERAGE']

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'minitest/hooks/test'
require 'active_fedora/cleaner'
require 'shoulda'

class ActiveSupport::TestCase

  include Minitest::Hooks
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # give this gibberish method a more semantically meaningful name for test-readers
  def generate_random_string
    Haikunator.haikunate
  end

  # clean ActiveFedora at the end of all tests in a given test class
  def after_all
    super
    ActiveFedora::Cleaner.clean!
  end

  # Add more helper methods to be used by all tests here...

  # Logs in a test user. Used for integration tests.
  def sign_in_as(user)
    # grab first user identitiy, dont care just need to login user
    identity = user.identities.first
    Rails.application.env_config['omniauth.auth'] = OmniAuth::AuthHash.new(
      provider: identity.provider,
      uid: identity.uid
    )
    post "/auth/#{identity.provider}/callback"
  end

  def as_user(user)
    ApplicationController.class_eval do
      alias_method :old_current_user, :current_user
      define_method :current_user, -> { return user }
    end

    yield

    ApplicationController.class_eval do
      alias_method :current_user, :old_current_user
    end
  end

  # Returns true if a test user is logged in.
  def logged_in?
    session[:user_id].present?
  end

  # turn on test mode for omniauth
  OmniAuth.config.test_mode = true

end
