class Assistant::Function::GetBalanceSheet < Assistant::Function
  include ActiveSupport::NumberHelper

  class << self
    def name
      "get_balance_sheet"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get the user's balance sheet with varying amounts of historical data.

        This is great for answering questions like:
        - What is the user's net worth?  What is it composed of?
        - How has the user's wealth changed over time?
      INSTRUCTIONS
    end
  end

  def call(params = {})
    observation_start_date = [ 5.years.ago.to_date, family.oldest_entry_date ].max

    period = Period.custom(start_date: observation_start_date, end_date: Date.current)

    net_worth = family.balance_sheet.net_worth_money
    assets_total = family.balance_sheet.assets.total_money
    liabilities_total = family.balance_sheet.liabilities.total_money

    {
      as_of_date: Date.current,
      oldest_account_start_date: family.oldest_entry_date,
      currency: family.currency,
      
      # Human-readable summary for AI
      summary: {
        headline: "Net worth of #{net_worth.format} as of #{Date.current.strftime('%b %d, %Y')}",
        assets_summary: "Total assets: #{assets_total.format}",
        liabilities_summary: "Total liabilities: #{liabilities_total.format}",
        health_indicator: debt_to_asset_health_message(assets_total.to_f, liabilities_total.to_f)
      },
      
      net_worth: {
        current: net_worth.format,
        monthly_history: historical_data(period)
      },
      assets: {
        current: assets_total.format,
        monthly_history: historical_data(period, classification: "asset")
      },
      liabilities: {
        current: liabilities_total.format,
        monthly_history: historical_data(period, classification: "liability")
      },
      insights: insights_data
    }
  end

  private
    def historical_data(period, classification: nil)
      scope = family.accounts.visible
      scope = scope.where(classification: classification) if classification.present?

      if period.start_date == Date.current
        []
      else
        account_ids = scope.pluck(:id)

        builder = Balance::ChartSeriesBuilder.new(
          account_ids: account_ids,
          currency: family.currency,
          period: period,
          favorable_direction: "up",
          interval: "1 month"
        )

        to_ai_time_series(builder.balance_series)
      end
    end

    def insights_data
      assets = family.balance_sheet.assets.total
      liabilities = family.balance_sheet.liabilities.total
      ratio = liabilities.zero? ? 0 : (liabilities / assets.to_f)

      {
        debt_to_asset_ratio: number_to_percentage(ratio * 100, precision: 0)
      }
    end

    def debt_to_asset_health_message(assets, liabilities)
      return "No assets recorded" if assets.zero?
      
      ratio = liabilities / assets
      
      case ratio
      when 0..0.2
        "Excellent financial health - very low debt"
      when 0.2..0.4
        "Good financial health - manageable debt"
      when 0.4..0.6
        "Moderate debt levels - consider paying down debt"
      else
        "High debt levels - debt reduction recommended"
      end
    end
end

