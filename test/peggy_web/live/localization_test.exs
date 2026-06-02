defmodule PeggyWeb.LocalizationTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures

  test "language switcher shows the three languages for a logged-in user", %{conn: conn} do
    {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/farms")
    assert html =~ "Bahasa Malaysia"
    assert html =~ "中文"
    assert html =~ "/locale/ms"
    assert html =~ "/locale/zh"
  end

  describe "ms translations" do
    test "core strings are translated" do
      assert t("ms", "Cancel") == "Batal"
      assert t("ms", "Save") == "Simpan"
      assert t("ms", "Reports") == "Laporan"
      assert t("ms", "Settings") == "Tetapan"
      assert t("ms", "Breeding") == "Pembiakan"
      assert t("ms", "Language") == "Bahasa"
      assert t("ms", "Weaning") == "Cerai susu"
      assert t("ms", "Boar") == "Babi jantan"
    end
  end

  describe "zh translations" do
    test "core strings are translated" do
      assert t("zh", "Cancel") == "取消"
      assert t("zh", "Save") == "保存"
      assert t("zh", "Reports") == "报告"
      assert t("zh", "Settings") == "设置"
      assert t("zh", "Breeding") == "繁殖"
      assert t("zh", "Language") == "语言"
      assert t("zh", "Weaning") == "断奶"
      assert t("zh", "Boar") == "公猪"
    end
  end

  test "a user with locale zh sees translated chrome", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Peggy.Accounts.update_user_locale(user, "zh")
    {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/farms")
    # "My farms" → 我的农场 appears in the navbar for a logged-in user
    assert html =~ "我的农场"
  end

  describe "error-domain translations" do
    test "common validation messages are translated" do
      assert de("ms", "can't be blank") == "tidak boleh kosong"
      assert de("zh", "can't be blank") == "不能为空"
      assert de("ms", "is invalid") == "tidak sah"
      assert de("zh", "is invalid") == "无效"
    end
  end

  test "language_switcher renders for anonymous when anonymous: true" do
    html =
      Phoenix.LiveViewTest.render_component(&PeggyWeb.Layouts.language_switcher/1, anonymous: true)

    assert html =~ "Bahasa Malaysia"
    assert html =~ "中文"
    assert html =~ "/locale/ms"
  end

  test "language_switcher renders nothing for anonymous by default" do
    html =
      Phoenix.LiveViewTest.render_component(&PeggyWeb.Layouts.language_switcher/1, current_scope: nil)

    assert html == "" or not (html =~ "/locale/ms")
  end

  defp t(locale, msgid) do
    Gettext.with_locale(PeggyWeb.Gettext, locale, fn ->
      Gettext.gettext(PeggyWeb.Gettext, msgid)
    end)
  end

  defp de(locale, msgid) do
    Gettext.with_locale(PeggyWeb.Gettext, locale, fn ->
      Gettext.dgettext(PeggyWeb.Gettext, "errors", msgid)
    end)
  end
end
