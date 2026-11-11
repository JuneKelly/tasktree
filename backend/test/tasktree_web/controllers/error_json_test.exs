defmodule TasktreeWeb.ErrorJSONTest do
  use TasktreeWeb.ConnCase, async: true

  test "renders 404 in the error contract shape" do
    assert TasktreeWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Not Found", details: %{}}}
  end

  test "renders 500" do
    assert %{error: %{code: "internal_server_error", message: "Internal Server Error"}} =
             TasktreeWeb.ErrorJSON.render("500.json", %{})
  end
end
