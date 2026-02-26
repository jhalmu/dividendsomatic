defmodule DividendsomaticWeb.PageControllerTest do
  use DividendsomaticWeb.ConnCase

  test "GET / shows portfolio page with about panel", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "dividends-o-matic"
  end
end
