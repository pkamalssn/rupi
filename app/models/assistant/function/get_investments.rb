# frozen_string_literal: true

class Assistant::Function::GetInvestments < Assistant::Function
  class << self
    def name
      "get_investments"
    end

    def description
      "Get user's investment holdings including stocks, mutual funds, PPF, EPF, NPS, and fixed deposits with current values and returns"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      properties: {
        type: {
          type: "string",
          description: "Filter by investment type. Use 'all' to get everything. Options: all, stocks, mutual_funds, ppf, epf, nps, fixed_deposits"
        }
      }
    )
  end

  def call(params = {})
    filter_type = params.fetch("type", "all")

    investment_accounts = family.accounts.where(accountable_type: "Investment")

    holdings_data = []
    total_value = 0

    investment_accounts.each do |account|
      account_value = account.balance

      account.holdings.each do |holding|
        next unless should_include_holding?(holding, filter_type)

        holding_data = {
          account_name: account.name,
          security_name: holding.security&.name || holding.name,
          ticker: holding.security&.ticker,
          quantity: holding.qty,
          current_price: holding.security&.current_price,
          current_value: holding.value,
          cost_basis: holding.cost_basis,
          gain_loss: calculate_gain_loss(holding),
          gain_loss_percent: calculate_gain_loss_percent(holding),
          currency: account.currency
        }

        holdings_data << holding_data
        total_value += holding.value || 0
      end

      # Include empty investment accounts
      if account.holdings.empty?
        holdings_data << {
          account_name: account.name,
          current_value: account_value,
          currency: account.currency,
          type: detect_investment_type(account)
        }
        total_value += account_value
      end
    end

    # Also include retirement accounts (PPF, EPF, NPS)
    if filter_type == "all" || filter_type.in?(%w[ppf epf nps])
      retirement_accounts = family.accounts.where("name ILIKE ANY (array[?, ?, ?])", "%PPF%", "%EPF%", "%NPS%")
      
      retirement_accounts.each do |account|
        holdings_data << {
          account_name: account.name,
          type: detect_investment_type(account),
          current_value: account.balance,
          currency: account.currency,
          is_tax_advantaged: true
        }
        total_value += account.balance
      end
    end

    {
      as_of_date: Date.current,
      summary: {
        headline: "Total investments of #{Money.new(total_value, family.currency).format} across #{holdings_data.size} holding(s)",
        investment_count: "#{investment_accounts.count} investment account(s)"
      },
      total_investment_value: total_value,
      total_investment_value_formatted: Money.new(total_value, family.currency).format,
      currency: family.currency,
      holdings_count: holdings_data.size,
      holdings: holdings_data.first(50)  # Limit to 50 holdings
    }
  end

  private

  def should_include_holding?(holding, filter_type)
    return true if filter_type == "all"

    case filter_type
    when "stocks"
      holding.security&.type == "Stock"
    when "mutual_funds"
      holding.security&.name&.match?(/fund|mf|mutual/i) || false
    else
      true
    end
  end

  def detect_investment_type(account)
    name = account.name.downcase
    
    case name
    when /ppf|public provident/
      "PPF"
    when /epf|employee provident/
      "EPF"
    when /nps|national pension/
      "NPS"
    when /fd|fixed deposit/
      "Fixed Deposit"
    when /mf|mutual fund|sip/
      "Mutual Fund"
    when /stock|equity|share/
      "Stocks"
    else
      "Investment"
    end
  end

  def calculate_gain_loss(holding)
    return nil unless holding.value && holding.cost_basis
    holding.value - holding.cost_basis
  end

  def calculate_gain_loss_percent(holding)
    return nil unless holding.cost_basis && holding.cost_basis > 0
    gain_loss = calculate_gain_loss(holding)
    return nil unless gain_loss
    
    ((gain_loss / holding.cost_basis) * 100).round(2)
  end
end
