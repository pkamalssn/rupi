class OtherLiability < ApplicationRecord
  include Accountable

  class << self
    def color
      "#ea580c"
    end

    def icon
      "minus"
    end

    def classification
      "liability"
    end
  end
end
