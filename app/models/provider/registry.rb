class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[exchange_rates securities llm]

  validates :concept, inclusion: { in: CONCEPTS }

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    def plaid_provider_for_region(region)
      region.to_sym == :us ? plaid_us : plaid_eu
    end

    private
      def stripe
        secret_key = ENV["STRIPE_SECRET_KEY"]
        webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

        return nil unless secret_key.present? && webhook_secret.present?

        Provider::Stripe.new(secret_key:, webhook_secret:)
      end

      def twelve_data
        api_key = ENV["TWELVE_DATA_API_KEY"].presence || Setting.twelve_data_api_key

        return nil unless api_key.present?

        Provider::TwelveData.new(api_key)
      end

      def plaid_us
        Provider::PlaidAdapter.ensure_configuration_loaded
        config = Rails.application.config.plaid

        return nil unless config.present?

        Provider::Plaid.new(config, region: :us)
      end

      def plaid_eu
        Provider::PlaidEuAdapter.ensure_configuration_loaded
        config = Rails.application.config.plaid_eu

        return nil unless config.present?

        Provider::Plaid.new(config, region: :eu)
      end

      def github
        Provider::Github.new
      end

      def openai
        access_token = ENV["OPENAI_ACCESS_TOKEN"].presence || Setting.openai_access_token

        return nil unless access_token.present?

        uri_base = ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base
        model = ENV["OPENAI_MODEL"].presence || Setting.openai_model

        if uri_base.present? && model.blank?
          Rails.logger.error("Custom OpenAI provider configured without a model; please set OPENAI_MODEL or Setting.openai_model")
          return nil
        end

        Provider::Openai.new(access_token, uri_base: uri_base, model: model)
      end

      # RUPI Engine provider - proxies to rupi-engine for all Gemini AI
      # Requires RUPI_ENGINE_URL and RUPI_ENGINE_API_KEY
      def engine
        engine_url = ENV["RUPI_ENGINE_URL"]
        
        # Engine provider is always available (will fail at runtime if not configured)
        # This allows the chat UI to work and show meaningful errors
        model = ENV["GOOGLE_AI_MODEL"].presence || Setting.google_ai_model
        
        Provider::Engine.new(model: model)
      end
      
      # DEPRECATED: Local Gemini provider (moved to rupi-engine)
      # Kept for backwards compatibility but returns nil
      def gemini
        Rails.logger.warn("Provider::Gemini is deprecated. Use Provider::Engine instead.")
        nil
      end

      def yahoo_finance
        Provider::YahooFinance.new
      end
  end

  def initialize(concept)
    @concept = concept
    validate!
  end

  def providers
    available_providers.map { |p| self.class.send(p) }.compact
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    self.class.send(provider_method)
  end

  private
    attr_reader :concept

    def available_providers
      case concept
      when :exchange_rates
        %i[twelve_data yahoo_finance]
      when :securities
        %i[twelve_data yahoo_finance]
      when :llm
        %i[engine]
      else
        %i[plaid_us plaid_eu github engine]
      end
    end
end
