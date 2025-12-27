class Investment < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "brokerage" => { short: "Brokerage", long: "Brokerage" },
    "pension" => { short: "Pension", long: "Pension" },
    "retirement" => { short: "Retirement", long: "Retirement" },
    "401k" => { short: "401(k)", long: "401(k)" },
    "roth_401k" => { short: "Roth 401(k)", long: "Roth 401(k)" },
    "403b" => { short: "403(b)", long: "403(b)" },
    "tsp" => { short: "TSP", long: "Thrift Savings Plan" },
    "529_plan" => { short: "529 Plan", long: "529 Plan" },
    "hsa" => { short: "HSA", long: "Health Savings Account" },
    "mutual_fund" => { short: "Mutual Fund", long: "Mutual Fund" },
    "mutual_fund_india" => { short: "MF India", long: "Mutual Fund (India - AMFI)" },
    "ppf" => { short: "PPF", long: "Public Provident Fund (India)" },
    "epf" => { short: "EPF", long: "Employees' Provident Fund (India)" },
    "nps" => { short: "NPS", long: "National Pension System (India)" },
    "nps_tier1" => { short: "NPS Tier I", long: "NPS Tier I Account" },
    "nps_tier2" => { short: "NPS Tier II", long: "NPS Tier II Account" },
    "sovereign_gold_bond" => { short: "SGB", long: "Sovereign Gold Bonds (India)" },
    "demat" => { short: "Demat", long: "Demat Account (NSE/BSE)" },
    "ulip" => { short: "ULIP", long: "Unit Linked Insurance Plan" },
    "ira" => { short: "IRA", long: "Traditional IRA" },
    "roth_ira" => { short: "Roth IRA", long: "Roth IRA" },
    "angel" => { short: "Angel", long: "Angel" }
  }.freeze

  class << self
    def color
      "#0d9488"
    end

    def classification
      "asset"
    end

    def icon
      "chart-line"
    end
  end
end
