# frozen_string_literal: true

# Migration to change default currency from USD to INR for Indian market
class ChangeDefaultCurrencyToInr < ActiveRecord::Migration[7.2]
  def up
    # Change default currency for balances
    change_column_default :balances, :currency, "INR"

    # Change default currency for budgets
    change_column_default :budgets, :currency, "INR"

    # Change default currency for budget_categories
    change_column_default :budget_categories, :currency, "INR"

    # Change default currency for entries (transactions, valuations, trades)
    change_column_default :entries, :currency, "INR"

    # Change default currency for holdings
    change_column_default :holdings, :currency, "INR"

    # Change default currency for security_prices
    change_column_default :security_prices, :currency, "INR"

    # Update existing USD values to INR for new families (optional - data migration)
    # This is a conservative approach - only change nil or USD defaults for future records
  end

  def down
    # Revert to USD defaults
    change_column_default :balances, :currency, "USD"
    change_column_default :budgets, :currency, "USD"
    change_column_default :budget_categories, :currency, "USD"
    change_column_default :entries, :currency, "USD"
    change_column_default :holdings, :currency, "USD"
    change_column_default :security_prices, :currency, "USD"
  end
end
