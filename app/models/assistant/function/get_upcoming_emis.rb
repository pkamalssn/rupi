# frozen_string_literal: true

class Assistant::Function::GetUpcomingEmis < Assistant::Function
  class << self
    def name
      "get_upcoming_emis"
    end

    def description
      "Get upcoming EMI payments due in the next 30 days with dates and amounts"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      properties: {
        days_ahead: {
          type: "integer",
          description: "Number of days to look ahead. Default is 30, max is 90."
        }
      }
    )
  end

  def call(params = {})
    days_ahead = params.fetch("days_ahead", 30).to_i
    days_ahead = [days_ahead, 90].min  # Max 90 days
    
    end_date = Date.current + days_ahead.days
    
    upcoming_emis = []
    total_due = 0

    loan_accounts = family.accounts.where(accountable_type: "Loan")

    loan_accounts.each do |account|
      loan = account.accountable
      next unless loan
      next unless loan.respond_to?(:emi_day) && loan.emi_day.present?

      emi_amount = loan.respond_to?(:emi_amount) ? (loan.emi_amount&.amount || 0) : 0
      next if emi_amount.zero?

      # Get upcoming EMI dates for this loan
      next unless loan.respond_to?(:upcoming_emi_dates)
      loan.upcoming_emi_dates(3).each do |emi_date|
        next if emi_date > end_date
        next if emi_date < Date.current

        days_until = (emi_date - Date.current).to_i

        upcoming_emis << {
          loan_name: account.name,
          lender: loan.lender_name,
          loan_type: Loan::SUBTYPES.dig(loan.subtype, :short) || loan.subtype,
          emi_amount: emi_amount,
          emi_formatted: Money.new(emi_amount, account.currency).format,
          due_date: emi_date.to_s,
          due_date_formatted: emi_date.strftime("%d %b %Y"),
          day_of_month: loan.emi_day,
          days_until: days_until,
          urgency: urgency_level(days_until),
          currency: account.currency
        }

        total_due += emi_amount
      end
    end

    # Sort by due date
    upcoming_emis.sort_by! { |emi| emi[:due_date] }

    # Group by week
    this_week = upcoming_emis.select { |e| e[:days_until] <= 7 }
    next_week = upcoming_emis.select { |e| e[:days_until] > 7 && e[:days_until] <= 14 }
    later = upcoming_emis.select { |e| e[:days_until] > 14 }

    {
      as_of_date: Date.current.to_s,
      looking_ahead_days: days_ahead,
      total_emis_due: upcoming_emis.size,
      total_amount_due: total_due,
      total_amount_formatted: Money.new(total_due, family.currency).format,
      currency: family.currency,
      summary: {
        this_week: {
          count: this_week.size,
          total: this_week.sum { |e| e[:emi_amount] }
        },
        next_week: {
          count: next_week.size,
          total: next_week.sum { |e| e[:emi_amount] }
        },
        later: {
          count: later.size,
          total: later.sum { |e| e[:emi_amount] }
        }
      },
      upcoming_emis: upcoming_emis
    }
  end

  private

  def urgency_level(days_until)
    case days_until
    when 0..2
      "critical"
    when 3..7
      "high"
    when 8..14
      "medium"
    else
      "low"
    end
  end
end
