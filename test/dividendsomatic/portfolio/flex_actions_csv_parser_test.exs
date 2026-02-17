defmodule Dividendsomatic.Portfolio.FlexActionsCsvParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.FlexActionsCsvParser

  @summary_and_transactions """
  "ClientAccountID","AccountAlias","Model","CurrencyPrimary","LevelOfDetail","FromDate","ToDate","StartingCash","StartingCashSecurities","StartingCashCommodities","ClientFees","ClientFeesSecurities","ClientFeesCommodities","Commissions","CommissionsSecurities","CommissionsCommodities","ReferralFee","ReferralFeeSecurities","ReferralFeeCommodities","CommissionCreditsRedemption","CommissionCreditsRedemptionSecurities","CommissionCreditsRedemptionCommodities","BillableCommissions","BillableCommissionsSecurities","BillableCommissionsCommodities","Deposit/Withdrawals","Deposit/WithdrawalsSecurities","Deposit/WithdrawalsCommodities","Deposits","DepositsSecurities","DepositsCommodities","Withdrawals","WithdrawalsSecurities","WithdrawalsCommodities","CarbonCredits","CarbonCreditsSecurities","CarbonCreditsCommodities","Donations","DonationsSecurities","DonationsCommodities","AccountTransfers","AccountTransfersSecurities","AccountTransfersCommodities","LinkingAdjustments","LinkingAdjustmentsSecurities","LinkingAdjustmentsCommodities","InternalTransfers","InternalTransfersSecurities","InternalTransfersCommodities","PaxosTransfers","PaxosTransfersSecurities","PaxosTransfersCommodities","ExcessFundSweep","ExcessFundSweepSec","ExcessFundSweepCom","DebitCardActivity","DebitCardActivitySecurities","DebitCardActivityCommodities","BillPay","BillPaySecurities","BillPayCommodities","Dividends","DividendsSecurities","DividendsCommodities","InsuredDepositInterest","InsuredDepositInterestSecurities","InsuredDepositInterestCommodities","BrokerInterest","BrokerInterestSecurities","BrokerInterestCommodities","BrokerFees","BrokerFeesSecurities","BrokerFeesCommodities","BondInterest","BondInterestSecurities","BondInterestCommodities","CashSettlingMtm","CashSettlingMtmSecurities","CashSettlingMtmCommodities","RealizedVm","RealizedVmSecurities","RealizedVmCommodities","RealizedForexVm","RealizedForexVmSecurities","RealizedForexVmCommodities","CFDCharges","CFDChargesSecurities","CFDChargesCommodities","NetTradesSales","NetTradesSalesSecurities","NetTradesSalesCommodities","NetTradesPurchases","NetTradesPurchasesSecurities","NetTradesPurchasesCommodities","AdvisorFees","AdvisorFeesSecurities","AdvisorFeesCommodities","FeesReceivables","FeesReceivablesSecurities","FeesReceivablesCommodities","PaymentInLieu","PaymentInLieuSecurities","PaymentInLieuCommodities","TransactionTax","TransactionTaxSecurities","TransactionTaxCommodities","TaxReceivables","TaxReceivablesSecurities","TaxReceivablesCommodities","WithholdingTax","WithholdingTaxSecurities","WithholdingTaxCommodities","871mWithholding","871mWithholdingSecurities","871mWithholdingCommodities","WithholdingTaxCollected","WithholdingTaxCollectedSecurities","WithholdingTaxCollectedCommodities","SalesTax","SalesTaxSecurities","SalesTaxCommodities","BillableSalesTax","BillableSalesTaxSecurities","BillableSalesTaxCommodities","ipoSubscription","ipoSubscriptionSecurities","ipoSubscriptionCommodities","FXTranslationGain/Loss","FXTranslationGain/LossSecurities","FXTranslationGain/LossCommodities","OtherFees","OtherFeesSecurities","OtherFeesCommodities","OtherIncome","OtherIncomeSecurities","OtherIncomeCommodities","Other","OtherSecurities","OtherCommodities","EndingCash","EndingCashSecurities","EndingCashCommodities","EndingSettledCash","EndingSettledCashSecurities","EndingSettledCashCommodities","StartingCashCollateralSLB","StartingCashCollateralSLBSecurities","StartingCashCollateralSLBCommodities","NetSecuritiesLentActivitySLB","NetSecuritiesLentActivitySLBSecurities","NetSecuritiesLentActivitySLBCommodities","EndingCashCollateralSLB","EndingCashCollateralSLBSecurities","EndingCashCollateralSLBCommodities","NetCashBalanceSLB","NetCashBalanceSLBSecurities","NetCashBalanceSLBCommodities","NetSettledCashBalanceSLB","NetSettledCashBalanceSLBSecurities","NetSettledCashBalanceSLBCommodities"
  "U7299935","","","BASE_SUMMARY","BaseCurrency","2026-02-09","2026-02-13","-228542.73","-228542.73","0","0","0","0","-23.47","-23.47","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","471.84","471.84","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","18.61","18.61","0","-28813.96","-28813.96","0","0","0","0","0","0","0","201.77","201.77","0","0","0","0","0","0","0","-115.29","-115.29","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","0","434.77","434.77","0","0","0","0","0","0","0","0","0","0","-256368.46","-256368.46","0","-240183.46","-240183.46","0","0","0","0","0","0","0","0","0","0","-256368.46","-256368.46","0","-240183.46","-240183.46","0"
  "ClientAccountID","AccountAlias","Model","CurrencyPrimary","FXRateToBase","AssetClass","Symbol","Description","Conid","SecurityID","SecurityIDType","CUSIP","ISIN","ListingExchange","UnderlyingConid","UnderlyingSymbol","UnderlyingSecurityID","UnderlyingListingExchange","Issuer","Multiplier","Strike","Expiry","Put/Call","PrincipalAdjustFactor","ReportDate","Date","SettleDate","ActivityCode","ActivityDescription","TradeID","OrderID","Buy/Sell","TradeQuantity","TradePrice","TradeGross","TradeCommission","TradeTax","Debit","Credit","Amount","TradeCode","Balance","LevelOfDetail","TransactionID"
  "U7299935","","","EUR","1","STK","TRIN","TRINITY CAPITAL","468533653","US8964423086","ISIN","896442308","US8964423086","NASDAQ","","TRIN","","","","1","","","","","2026-02-09","2026-01-15","2026-01-15","FRTAX","TRIN tax","","","","0","0","0","0","0","","10.08","10.08","","-228532.65","BaseCurrency","5393915966"
  "U7299935","","","EUR","1","STK","ORC","ORCHID ISLAND","581240386","US68571X3017","ISIN","68571X301","US68571X3017","NYSE","","ORC","","","","1","","","","","2026-02-10","2026-02-10","2026-02-11","BUY","Buy 2000 ORC","","","BUY","2000","7.5","-12610.35","-8.41","0","-12618.76","","-12618.76","","-241104.96","BaseCurrency","5400494781"
  "U7299935","","","EUR","1","STK","AGNC","AGNC INVESTMENT","249963585","US00123Q1040","ISIN","00123Q104","US00123Q1040","NASDAQ","","AGNC","","","","1","","","","","2026-02-10","2026-02-10","2026-02-10","PIL","AGNC PIL","","","","0","0","0","0","0","","201.77","201.77","","-240903.20","BaseCurrency","5401920872"
  "U7299935","","","EUR","1","STK","TELIA1","TELIA CO AB","16660531","SE0000667925","ISIN","","SE0000667925","FWB","","TLS","","","","1","","","","","2026-02-12","2026-02-11","2026-02-11","DIV","TLS dividend","","","","0","0","0","0","0","","471.84","471.84","","-240464.55","BaseCurrency","5415909234"
  "U7299935","","","EUR","1","STK","NDA FI","NORDEA BANK","335134428","FI4000297767","ISIN","","FI4000297767","HEX","","NDA FI","","","","1","","","","","2026-02-13","2026-02-13","2026-02-17","BUY","Buy 1000 NDA FI","","","BUY","1000","16.185","-16185","-12.14","0","-16197.14","","-16197.14","","-256803.23","BaseCurrency","5424348166"
  """

  describe "parse/1" do
    test "should extract transactions from the detail section" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)
      assert data.transactions != []
    end

    test "should parse transaction fields correctly" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)

      telia =
        Enum.find(data.transactions, fn txn ->
          txn.symbol == "TELIA1" and txn.activity_code == "DIV"
        end)

      assert telia != nil
      assert telia.isin == "SE0000667925"
      assert telia.date == ~D[2026-02-11]
      assert Decimal.equal?(telia.amount, Decimal.new("471.84"))
    end

    test "should classify activity codes" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)

      codes = Enum.map(data.transactions, & &1.activity_code) |> Enum.uniq() |> Enum.sort()
      assert "BUY" in codes
      assert "DIV" in codes
      assert "FRTAX" in codes
      assert "PIL" in codes
    end

    test "should parse buy transactions with trade details" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)

      buy = Enum.find(data.transactions, &(&1.symbol == "NDA FI"))
      assert buy.buy_sell == "BUY"
      assert Decimal.equal?(buy.trade_quantity, Decimal.new("1000"))
      assert Decimal.equal?(buy.trade_price, Decimal.new("16.185"))
    end

    test "should extract summary data from BASE_SUMMARY" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)

      assert data.summary.from_date == ~D[2026-02-09]
      assert data.summary.to_date == ~D[2026-02-13]
      assert data.summary.dividends != nil
      assert data.summary.ending_cash != nil
    end

    test "should filter out ADJ rows" do
      {:ok, data} = FlexActionsCsvParser.parse(@summary_and_transactions)

      adj_rows = Enum.filter(data.transactions, &(&1.activity_code == "ADJ"))
      assert adj_rows == []
    end

    test "should return error for empty CSV" do
      assert {:error, :empty_csv} = FlexActionsCsvParser.parse("")
    end
  end
end
