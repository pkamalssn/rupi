class Depository < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "checking" => { short: "Checking", long: "Checking" },
    "savings" => { short: "Savings", long: "Savings" },
    "salary" => { short: "Salary", long: "Salary Account" },
    "current" => { short: "Current", long: "Current Account (India)" },
    "nre" => { short: "NRE", long: "NRE Account (NRI)" },
    "nro" => { short: "NRO", long: "NRO Account (NRI)" },
    "fcnr" => { short: "FCNR", long: "FCNR Account (NRI)" },
    "hsa" => { short: "HSA", long: "Health Savings Account" },
    "cd" => { short: "CD", long: "Certificate of Deposit" },
    "fd" => { short: "FD", long: "Fixed Deposit (India)" },
    "rd" => { short: "RD", long: "Recurring Deposit (India)" },
    "money_market" => { short: "MM", long: "Money Market" },
    "digital_bank" => { short: "Digital", long: "Digital Bank (Paytm, Airtel, etc.)" }
  }.freeze

  class << self
    def display_name
      "Cash"
    end

    def color
      "#16a34a"
    end

    def classification
      "asset"
    end

    def icon
      "landmark"
    end
  end
end
