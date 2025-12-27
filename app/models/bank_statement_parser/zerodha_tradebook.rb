# frozen_string_literal: true

module BankStatementParser
  class ZerodhaTradebook < Base
    # Zerodha Tradebook CSV parser
    # Columns: symbol, isin, trade_date, exchange, segment, series, trade_type, auction, quantity, price, trade_id, order_id, order_execution_time
    
    def parse
      if csv_file?
        parse_csv
      elsif excel_file?
        parse_excel
      else
        raise UnsupportedFormatError, "Zerodha tradebooks are typically CSV format"
      end
    rescue => e
      raise ParseError, "Failed to parse Zerodha tradebook: #{e.message}"
    end

    private

    def csv_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.csv$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("csv")
    end

    def excel_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.xlsx?$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("excel") || file.content_type&.include?("spreadsheet")
    end

    def parse_csv
      require "csv"
      trades = []
      
      CSV.foreach(file_path, headers: true) do |row|
        trade = parse_trade_row(row.to_h)
        trades << trade if trade
      end

      trades
    end

    def parse_excel
      require "roo"
      spreadsheet = Roo::Spreadsheet.open(file_path)
      
      trades = []
      headers = nil
      
      spreadsheet.each_with_index do |row, idx|
        if idx == 0
          headers = row.map { |h| h.to_s.downcase.strip }
          next
        end
        
        row_hash = headers.zip(row).to_h
        trade = parse_trade_row(row_hash)
        trades << trade if trade
      end

      trades
    end

    def parse_trade_row(row)
      # Handle both exact column names and variations
      symbol = row["symbol"] || row["Symbol"] || row["scrip"]
      return nil unless symbol.present?

      trade_date = parse_date(row["trade_date"] || row["Trade Date"] || row["date"])
      return nil unless trade_date

      quantity = (row["quantity"] || row["Quantity"] || row["qty"]).to_f
      price = (row["price"] || row["Price"] || row["rate"]).to_f
      trade_type = (row["trade_type"] || row["Trade Type"] || row["type"]).to_s.downcase
      
      return nil if quantity == 0 || price == 0

      # Calculate trade value
      trade_value = quantity * price
      
      # For investment tracking: buy = money out (negative), sell = money in (positive)
      amount = trade_type == "buy" ? -trade_value : trade_value

      {
        date: trade_date,
        amount: BigDecimal(amount.to_s),
        description: "#{trade_type.capitalize} #{quantity.to_i} #{symbol} @ ₹#{price.round(2)}",
        notes: "Zerodha Trade - #{row["exchange"]} #{row["segment"]}",
        metadata: {
          trade_type: trade_type,
          symbol: symbol,
          isin: row["isin"] || row["ISIN"],
          quantity: quantity,
          price: price,
          exchange: row["exchange"],
          segment: row["segment"],
          trade_id: row["trade_id"],
          order_id: row["order_id"]
        }
      }
    end

    # Additional method to get summarized holdings from trades
    def summarize_holdings
      trades = parse
      holdings = {}
      
      trades.each do |trade|
        next unless trade[:metadata]
        
        symbol = trade[:metadata][:symbol]
        holdings[symbol] ||= { quantity: 0, total_cost: 0, trades: [] }
        
        qty = trade[:metadata][:quantity]
        price = trade[:metadata][:price]
        
        if trade[:metadata][:trade_type] == "buy"
          holdings[symbol][:quantity] += qty
          holdings[symbol][:total_cost] += qty * price
        else
          holdings[symbol][:quantity] -= qty
          holdings[symbol][:total_cost] -= qty * price
        end
        
        holdings[symbol][:trades] << trade
      end
      
      # Calculate average cost for remaining holdings
      holdings.transform_values do |data|
        if data[:quantity] > 0
          data[:avg_cost] = data[:total_cost] / data[:quantity]
        end
        data
      end
    end
  end
end
