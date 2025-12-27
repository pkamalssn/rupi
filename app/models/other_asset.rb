class OtherAsset < ApplicationRecord
  include Accountable

  class << self
    def color
      "#06b6d4"
    end

    def icon
      "plus"
    end

    def classification
      "asset"
    end
  end
end
