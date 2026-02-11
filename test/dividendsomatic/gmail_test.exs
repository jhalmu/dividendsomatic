defmodule Dividendsomatic.GmailTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Gmail
  alias Dividendsomatic.Portfolio

  describe "extract_date_from_subject/1" do
    test "should extract date from valid subject" do
      assert Gmail.extract_date_from_subject("Activity Flex for 28/01/2026") == ~D[2026-01-28]
    end

    test "should extract date with different months" do
      assert Gmail.extract_date_from_subject("Activity Flex for 25/12/2025") == ~D[2025-12-25]
      assert Gmail.extract_date_from_subject("Activity Flex for 15/06/2026") == ~D[2026-06-15]
      assert Gmail.extract_date_from_subject("Activity Flex for 28/02/2026") == ~D[2026-02-28]
    end

    test "should return today's date for non-matching subject" do
      assert Gmail.extract_date_from_subject("Random email subject") == Date.utc_today()
    end

    test "should return today's date for partial match" do
      assert Gmail.extract_date_from_subject("Activity Flex") == Date.utc_today()
    end

    test "should return today's date for invalid date values" do
      assert Gmail.extract_date_from_subject("Activity Flex for 32/01/2026") == Date.utc_today()
    end

    test "should return today's date for empty string" do
      assert Gmail.extract_date_from_subject("") == Date.utc_today()
    end

    test "should handle subject with extra text" do
      assert Gmail.extract_date_from_subject("Fwd: Activity Flex for 15/03/2026 - Report") ==
               ~D[2026-03-15]
    end
  end

  describe "search_activity_flex_emails/1" do
    test "should return empty list when OAuth not configured" do
      {:ok, emails} = Gmail.search_activity_flex_emails()
      assert emails == []
    end

    test "should accept options" do
      {:ok, emails} = Gmail.search_activity_flex_emails(max_results: 10, days_back: 7)
      assert emails == []
    end
  end

  describe "get_csv_from_email/1" do
    test "should return not_configured without OAuth" do
      assert Gmail.get_csv_from_email("test_id") == {:error, :not_configured}
    end
  end

  describe "import_all_new/1" do
    test "should return zero counts when no emails found" do
      {:ok, summary} = Gmail.import_all_new()

      assert summary.imported == 0
      assert summary.skipped == 0
      assert summary.errors == 0
    end

    test "should accept options for import" do
      {:ok, summary} = Gmail.import_all_new(days_back: 7, max_results: 5)

      assert summary.imported == 0
      assert summary.skipped == 0
      assert summary.errors == 0
    end
  end

  describe "import_email skipping" do
    @csv_data """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    """

    test "should not create duplicate snapshots for same date" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      # Verify snapshot exists
      snapshot = Portfolio.get_snapshot_by_date(~D[2026-01-28])
      assert snapshot != nil

      # Attempting to import same date again should fail with unique constraint
      assert {:error, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
    end
  end
end
