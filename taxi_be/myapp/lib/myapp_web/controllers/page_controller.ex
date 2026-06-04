defmodule MyappWeb.PageController do
  use MyappWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
