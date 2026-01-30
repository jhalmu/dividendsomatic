defmodule DividendsomaticWeb.PageControllerTest do
  use DividendsomaticWeb.ConnCase

  test "GET / shows portfolio page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "No Portfolio Data"
  end
end
