class DOIRemovalJob < ActiveJob::Base
  queue_as :default

  def perform(doi)
    Hydranorth::DOIService.remove(doi)
  end
end
