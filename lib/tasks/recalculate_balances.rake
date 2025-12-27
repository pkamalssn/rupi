namespace :accounts do
  desc "Recalculate account balances from transactions for all manual accounts"
  task recalculate_balances: :environment do
    Account.manual.find_each do |account|
      puts "Syncing account: #{account.name} (ID: #{account.id})"
      account.sync_later
    end

    puts "Scheduled sync jobs for #{Account.manual.count} manual accounts"
    puts "Jobs will run automatically via GoodJob (async mode in Puma)"
  end

  desc "Recalculate balances synchronously for all manual accounts"
  task recalculate_balances_now: :environment do
    Account.manual.find_each do |account|
      puts "Syncing account: #{account.name} (ID: #{account.id})"
      
      sync = account.syncs.create!(
        window_start_date: account.entries.minimum(:date),
        window_end_date: account.entries.maximum(:date)
      )
      
      account.perform_sync(sync)
      account.update!(balance: account.balances.order(date: :desc).first&.end_balance || 0)
      puts "  Balance updated to: #{account.balance}"
    end

    puts "Balances recalculated for #{Account.manual.count} manual accounts"
  end
end
