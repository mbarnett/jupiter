class DOIServiceJob < ActiveJob::Base
  queue_as :default

  def perform(work_id, type = 'create')
    work = Work.find(work_id)
    Hydranorth::DOIService.new(work).send(type) if work
  end
end
