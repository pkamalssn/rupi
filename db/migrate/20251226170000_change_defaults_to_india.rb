class ChangeDefaultsToIndia < ActiveRecord::Migration[7.2]
  def up
    # Change Family defaults to India-centric values
    change_column_default :families, :currency, from: "USD", to: "INR"
    change_column_default :families, :country, from: "US", to: "IN"
    change_column_default :families, :date_format, from: "%m-%d-%Y", to: "%d-%m-%Y"
  end

  def down
    # Revert to original US defaults
    change_column_default :families, :currency, from: "INR", to: "USD"
    change_column_default :families, :country, from: "IN", to: "US"
    change_column_default :families, :date_format, from: "%d-%m-%Y", to: "%m-%d-%Y"
  end
end
