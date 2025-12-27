class SyncAllJob < ApplicationJob
  queue_as :scheduled
  # GoodJob concurrency control (replaces sidekiq-unique-jobs)
  good_job_control_concurrency_with(
    total_limit: 1,
    key: -> { "sync_all_job" }
  )

  def perform
    Rails.logger.info("Starting sync for all families")
    Family.find_each do |family|
      family.sync_later
    rescue => e
      Rails.logger.error("Failed to sync family #{family.id}: #{e.message}")
    end
    Rails.logger.info("Completed sync for all families")
  end
end
