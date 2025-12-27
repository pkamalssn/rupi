# RUPI Version Module
# Get ready to manage your Rupees easier with RUPI!

module Rupi
  class << self
    def version
      "2.3"
    end

    def full_version
      "RUPI v#{version}"
    end

    def tagline
      "Get ready to manage your Rupees easier with RUPI!"
    end
  end
end

# Keep Sure module as alias for backwards compatibility with Rails internals
module Sure
  class << self
    def version
      Semver.new("2.3.0")
    end

    def commit_sha
      if Rails.env.production?
        ENV["BUILD_COMMIT_SHA"]
      else
        `git rev-parse HEAD`.chomp rescue nil
      end
    end
  end
end
