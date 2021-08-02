defmodule Peggy.Company do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Peggy.Repo
  alias Peggy.Company.Farm
  alias Peggy.Company.FarmUser

  def roles do
    ["admin", "manager", "supervisor", "operator", "clerk"]
  end

  def countries do
    ["Afganistan", "Albania", "Algeria", "American Samoa", "Andorra", "Anguilla", "Antigua & Barbuda",
     "Argentina", "Armenia", "Aruba", "Australia", "Austria", "Azerbaijan",
     "Bahamas", "Bahrain", "Bangladesh", "Barbados", "Belarus",
     "Belgium", "Belize", "Benin", "Bermuda", "Bhutan", "Bolivia",
     "Bonaire", "Bosnia & Herzegovina", "Botswana", "Brazil",
     "British Indian Ocean Ter", "Brunei", "Bulgaria", "Burkina Faso", "Burundi",
     "Cambodia", "Cameroon", "Canada", "Canary Islands", "Cape Verde", "Cayman Islands",
     "Central African Republic", "Chad", "Channel Islands", "Chile", "China", "Christmas Island",
     "Cocos Island", "Colombia", "Comoros", "Congo", "Cook Islands", "Costa Rica", "Cote DIvoire",
     "Croatia", "Cuba", "Curaco", "Cyprus", "Czech Republic", "Denmark", "Djibouti", "Dominica",
     "Dominican Republic", "East Timor", "Ecuador", "Egypt", "El Salvador", "Equatorial Guinea",
     "Eritrea", "Estonia", "Ethiopia", "Falkland Islands", "Faroe Islands", "Fiji", "Finland", "France",
     "French Guiana", "French Polynesia", "French Southern Ter", "Gabon", "Gambia", "Georgia", "Germany",
     "Ghana", "Gibraltar", "Great Britain", "Greece", "Greenland", "Grenada", "Guadeloupe", "Guam", "Guatemala",
     "Guinea", "Guyana", "Haiti", "Hawaii", "Honduras", "Hong Kong", "Hungary", "Iceland", "Indonesia",
     "India", "Iran", "Iraq", "Ireland", "Isle of Man", "Israel", "Italy", "Jamaica", "Japan", "Jordan",
     "Kazakhstan", "Kenya", "Kiribati", "Korea North", "Korea Sout", "Kuwait", "Kyrgyzstan", "Laos",
     "Latvia", "Lebanon", "Lesotho", "Liberia", "Libya", "Liechtenstein", "Lithuania", "Luxembourg",
     "Macau", "Macedonia", "Madagascar", "Malaysia", "Malawi", "Maldives", "Mali", "Malta",
     "Marshall Islands", "Martinique", "Mauritania", "Mauritius", "Mayotte", "Mexico", "Midway Islands",
     "Moldova", "Monaco", "Mongolia", "Montserrat", "Morocco", "Mozambique", "Myanmar", "Nambia", "Nauru",
     "Nepal", "Netherland Antilles", "Netherlands", "Nevis", "New Caledonia", "New Zealand", "Nicaragua",
     "Niger", "Nigeria", "Niue", "Norfolk Island", "Norway", "Oman", "Pakistan", "Palau Island", "Palestine",
     "Panama", "Papua New Guinea", "Paraguay", "Peru", "Phillipines", "Pitcairn Island", "Poland", "Portugal",
     "Puerto Rico", "Qatar", "Republic of Montenegro", "Republic of Serbia", "Reunion", "Romania", "Russia",
     "Rwanda", "St Barthelemy", "St Eustatius", "St Helena", "St Kitts-Nevis", "St Lucia", "St Maarten",
     "St Pierre & Miquelon", "St Vincent & Grenadines", "Saipan", "Samoa", "Samoa American", "San Marino",
     "Sao Tome & Principe", "Saudi Arabia", "Senegal", "Seychelles", "Sierra Leone", "Singapore", "Slovakia",
     "Slovenia", "Solomon Islands", "Somalia", "South Africa", "Spain", "Sri Lanka", "Sudan", "Suriname",
     "Swaziland", "Sweden", "Switzerland", "Syria", "Tahiti", "Taiwan", "Tajikistan", "Tanzania", "Thailand",
     "Togo", "Tokelau", "Tonga", "Trinidad & Tobago", "Tunisia", "Turkey", "Turkmenistan", "Turks & Caicos Is",
     "Tuvalu", "Uganda", "United Kingdom", "Ukraine", "United Arab Erimates", "United States of America",
     "Uraguay", "Uzbekistan", "Vanuatu", "Vatican City State", "Venezuela", "Vietnam", "Virgin Islands (Brit)",
     "Virgin Islands (USA)", "Wake Island", "Wallis & Futana Is", "Yemen", "Zaire", "Zambia", "Zimbabwe"]
  end

  def list_farms(user) do
    Repo.all(
      from f in Farm,
        join: fu in FarmUser,
        on: fu.user_id == ^user.id and f.id == fu.farm_id,
        order_by: f.name
    )
  end

  def get_farm!(id, user) do
    Repo.get!(
      from(f in Farm,
        join: fu in FarmUser,
        on: fu.user_id == ^user.id and f.id == fu.farm_id,
        select: f,
        order_by: f.name
      ),
      id
    )
  end

  def farm_exists?(user) do
    if user do
      Repo.exists?(
        from f in Farm,
          join: fu in FarmUser,
          on: fu.user_id == ^user.id and f.id == fu.farm_id
      )
    else
      false
    end
  end

  def create_farm(attrs \\ %{}, user) do
    Multi.new()
    |> Multi.insert(:farm, Farm.changeset(%Farm{}, attrs, user))
    |> Multi.insert(:farm_user, fn %{farm: farm} ->
      Ecto.build_assoc(farm, :farm_user, role: "admin", user_id: user.id)
    end)
    |> Peggy.Repo.transaction()
    |> case do
      {:ok, %{farm: farm}} -> {:ok, farm}
      {:error, :farm, changeset, _} -> {:error, changeset}
    end
  end

  def delete_farm(%Farm{} = farm, user) do
    if is_user_admin?(user, farm) do
      Repo.delete(farm)
    else
      raise "Not Authorized"
    end
  end

  def user_role_in_farm(user, farm) do
    roles =
      Repo.all(
        from fu in FarmUser,
          where: fu.user_id == ^user.id and fu.farm_id == ^farm.id,
          select: fu.role
      )

    case roles do
      [role] -> role
      _ -> :no_access
    end
  end

  def allow_user_access_farm(user, farm, role, admin) do
    if is_user_admin?(admin, farm) do
      %FarmUser{}
      |> FarmUser.changeset(%{user_id: user.id, farm_id: farm.id, role: role})
      |> Repo.insert()
    else
      raise "Not Authorized"
    end
  end

  def change_user_role_in_farm(user, farm, role, admin) do
    if(user == admin, do: raise("Cannot change own role"))

    if is_user_admin?(admin, farm) do
      fu = Repo.get_by(FarmUser, farm_id: farm.id, user_id: user.id)

      FarmUser.changeset(fu, %{role: role})
      |> Repo.update()
    else
      raise "Not Authorized"
    end
  end

  def update_farm(%Farm{} = farm, attrs, user) do
    if is_user_admin?(user, farm) do
      farm
      |> Farm.changeset(attrs, user)
      |> Repo.update()
    else
      raise "Not Authorized"
    end
  end

  def change_farm(%Farm{} = farm, attrs \\ %{}, user) do
    Farm.changeset(farm, attrs, user)
  end

  defp is_user_admin?(user, farm) do
    user_role_in_farm(user, farm) == "admin"
  end

  alias Peggy.Company.InviteUser

  def list_invite_users do
    Repo.all(InviteUser)
  end

  def get_invite_user!(id), do: Repo.get!(InviteUser, id)

  def create_invite_user(attrs \\ %{}) do
    %InviteUser{}
    |> InviteUser.changeset(attrs)
    |> Repo.insert()
  end

  def update_invite_user(%InviteUser{} = invite_user, attrs) do
    invite_user
    |> InviteUser.changeset(attrs)
    |> Repo.update()
  end

  def delete_invite_user(%InviteUser{} = invite_user) do
    Repo.delete(invite_user)
  end

  def change_invite_user(%InviteUser{} = invite_user, attrs \\ %{}) do
    InviteUser.changeset(invite_user, attrs)
  end
end
