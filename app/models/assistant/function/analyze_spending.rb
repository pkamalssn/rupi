# frozen_string_literal: true

class Assistant::Function::AnalyzeSpending < Assistant::Function
  class << self
    def name
      "analyze_spending"
    end

    def description
      "Analyze spending patterns, find anomalies, compare periods, and identify top spending categories"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      properties: {
        period: {
          type: "string",
          description: "Time period to analyze. Options: this_month, last_month, last_3_months, last_6_months, this_year"
        },
        category: {
          type: "string",
          description: "Optional: Filter analysis to a specific category"
        },
        compare_previous: {
          type: "boolean",
          description: "Compare with the previous period of same duration. Default: true"
        }
      }
    )
  end

  def call(params = {})
    period_name = params.fetch("period", "this_month")
    category_filter = params["category"]
    compare = params.fetch("compare_previous", true)

    period = calculate_period(period_name)
    previous_period = calculate_previous_period(period_name) if compare

    # Get transactions (which have entries) - expenses are entries with positive amounts
    transactions = family.transactions
      .joins(:entry)
      .where(entries: { date: period[:start]..period[:end] })
      .where("entries.amount > 0")  # Expenses have positive amounts in this system

    if category_filter.present?
      transactions = transactions.joins(:category)
        .where("categories.name ILIKE ?", "%#{category_filter}%")
    end

    # Calculate totals using entries
    total_spent = transactions.joins(:entry).sum("entries.amount")
    
    # Category breakdown
    category_spending = transactions
      .joins(:category)
      .joins(:entry)
      .group("categories.name")
      .sum("entries.amount")
      .sort_by { |_, v| -v }
      .to_h

    # Top merchants
    merchant_spending = transactions
      .joins(:merchant)
      .joins(:entry)
      .group("merchants.name")
      .sum("entries.amount")
      .sort_by { |_, v| -v }
      .first(10)
      .to_h

    # Daily spending pattern
    daily_spending = transactions
      .joins(:entry)
      .group("entries.date")
      .sum("entries.amount")

    avg_daily = daily_spending.values.sum / [daily_spending.size, 1].max

    # Find anomalies (days with >2x average spending)
    anomalies = daily_spending
      .select { |_, amount| amount > avg_daily * 2 }
      .sort_by { |_, v| -v }
      .first(5)
      .map { |date, amount| { date: date.to_s, amount: amount, formatted: Money.new(amount, family.currency).format } }

    result = {
      period: {
        name: period_name,
        start_date: period[:start].to_s,
        end_date: period[:end].to_s
      },
      total_spent: total_spent,
      total_spent_formatted: Money.new(total_spent, family.currency).format,
      transaction_count: transactions.count,
      average_daily_spending: avg_daily.round(2),
      average_daily_formatted: Money.new(avg_daily, family.currency).format,
      currency: family.currency,
      
      top_categories: category_spending.first(10).map do |name, amount|
        {
          name: name,
          amount: amount,
          formatted: Money.new(amount, family.currency).format,
          percentage: total_spent > 0 ? ((amount / total_spent) * 100).round(1) : 0
        }
      end,
      
      top_merchants: merchant_spending.map do |name, amount|
        {
          name: name,
          amount: amount,
          formatted: Money.new(amount, family.currency).format
        }
      end,
      
      spending_anomalies: anomalies,
      anomalies_found: anomalies.any?
    }

    # Add comparison if requested
    if compare && previous_period
      previous_transactions = family.transactions
        .joins(:entry)
        .where(entries: { date: previous_period[:start]..previous_period[:end] })
        .where("entries.amount > 0")

      if category_filter.present?
        previous_transactions = previous_transactions.joins(:category)
          .where("categories.name ILIKE ?", "%#{category_filter}%")
      end

      previous_total = previous_transactions.joins(:entry).sum("entries.amount")
      change = total_spent - previous_total
      change_percent = previous_total > 0 ? ((change / previous_total) * 100).round(1) : 0

      result[:comparison] = {
        previous_period: {
          start_date: previous_period[:start].to_s,
          end_date: previous_period[:end].to_s
        },
        previous_total: previous_total,
        previous_formatted: Money.new(previous_total, family.currency).format,
        change: change,
        change_formatted: Money.new(change.abs, family.currency).format,
        change_percent: change_percent,
        trend: change > 0 ? "increased" : (change < 0 ? "decreased" : "unchanged")
      }
    end

    # Add human-readable summary for AI to use
    top_category = category_spending.first
    result[:summary] = {
      headline: "Total spending of #{Money.new(total_spent, family.currency).format} from #{period[:start].strftime('%b %d, %Y')} to #{period[:end].strftime('%b %d, %Y')}",
      top_spending_category: top_category ? "#{top_category[0]} at #{Money.new(top_category[1], family.currency).format}" : "No categories found",
      daily_average: "Average daily spending: #{Money.new(avg_daily, family.currency).format}",
      transaction_volume: "#{transactions.count} transactions in this period"
    }

    result
  end

  private

  def calculate_period(period_name)
    case period_name
    when "this_month"
      { start: Date.current.beginning_of_month, end: Date.current }
    when "last_month"
      last_month = Date.current - 1.month
      { start: last_month.beginning_of_month, end: last_month.end_of_month }
    when "last_3_months"
      { start: 3.months.ago.beginning_of_month, end: Date.current }
    when "last_6_months"
      { start: 6.months.ago.beginning_of_month, end: Date.current }
    when "this_year"
      { start: Date.current.beginning_of_year, end: Date.current }
    else
      { start: Date.current.beginning_of_month, end: Date.current }
    end
  end

  def calculate_previous_period(period_name)
    case period_name
    when "this_month"
      last_month = Date.current - 1.month
      { start: last_month.beginning_of_month, end: last_month.end_of_month }
    when "last_month"
      two_months_ago = Date.current - 2.months
      { start: two_months_ago.beginning_of_month, end: two_months_ago.end_of_month }
    when "last_3_months"
      { start: 6.months.ago.beginning_of_month, end: 3.months.ago.end_of_month }
    when "last_6_months"
      { start: 12.months.ago.beginning_of_month, end: 6.months.ago.end_of_month }
    when "this_year"
      last_year = Date.current.year - 1
      { start: Date.new(last_year, 1, 1), end: Date.new(last_year, 12, 31) }
    end
  end
end
