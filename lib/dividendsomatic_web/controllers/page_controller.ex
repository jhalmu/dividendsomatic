defmodule DividendsomaticWeb.PageController do
  use DividendsomaticWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
