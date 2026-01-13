class ApplicationJob < ActiveJob::Base
  include GoodJob::ActiveJobExtensions::Concurrency

  retry_on ActiveRecord::Deadlocked
  discard_on ActiveJob::DeserializationError
  queue_as :low_priority # default queue
end
