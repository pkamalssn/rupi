# frozen_string_literal: true

Rails.application.configure do
  config.good_job = {
    # Enable async execution mode - runs jobs inside the Puma web server process
    # This is perfect for Render.com's free tier (no separate worker needed)
    execution_mode: :async,

    # Enable cron for scheduled jobs (replaces sidekiq-cron)
    enable_cron: true,

    # Number of threads for async execution (adjust based on your needs)
    # Keep this low to avoid starving web requests
    max_threads: 3,

    # Poll interval for checking new jobs (in seconds)
    poll_interval: 5,

    # Shutdown timeout (in seconds)
    shutdown_timeout: 25,

    # Cleanup settings for finished jobs
    cleanup_preserved_jobs_before_seconds_ago: 7.days.to_i,
    cleanup_interval_seconds: 1.hour.to_i,
    cleanup_discarded_jobs: true,

    # Scheduled jobs (migrated from sidekiq-cron)
    cron: {
      # Sync all families every 12 hours
      sync_all: {
        cron: "0 */12 * * *",  # Every 12 hours
        class: "SyncAllJob",
        description: "Sync all families with external data sources"
      }
    }
  }
end

# Dashboard authentication (production only)
# Uses same credentials as the old Sidekiq dashboard
if Rails.env.production?
  GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
    configured_username = ENV.fetch("GOOD_JOB_USERNAME", "rupi")
    configured_password = ENV.fetch("GOOD_JOB_PASSWORD", "rupi")

    ActiveSupport::SecurityUtils.secure_compare(username, configured_username) &&
      ActiveSupport::SecurityUtils.secure_compare(password, configured_password)
  end
end
