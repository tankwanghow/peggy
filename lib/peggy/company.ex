defmodule Peggy.Company do
  import Ecto.Query, warn: false
  import Peggy.Authorization

  alias Ecto.Multi
  alias Peggy.Repo
  alias Peggy.Company.Farm
  alias Peggy.Company.FarmUser
  alias Peggy.UserAccounts.User

  def roles do
    ["guest", "admin", "manager", "supervisor", "operator", "clerk", "disable"]
  end

  def countries do
    [
      "Afganistan",
      "Albania",
      "Algeria",
      "American Samoa",
      "Andorra",
      "Anguilla",
      "Antigua & Barbuda",
      "Argentina",
      "Armenia",
      "Aruba",
      "Australia",
      "Austria",
      "Azerbaijan",
      "Bahamas",
      "Bahrain",
      "Bangladesh",
      "Barbados",
      "Belarus",
      "Belgium",
      "Belize",
      "Benin",
      "Bermuda",
      "Bhutan",
      "Bolivia",
      "Bonaire",
      "Bosnia & Herzegovina",
      "Botswana",
      "Brazil",
      "British Indian Ocean Ter",
      "Brunei",
      "Bulgaria",
      "Burkina Faso",
      "Burundi",
      "Cambodia",
      "Cameroon",
      "Canada",
      "Canary Islands",
      "Cape Verde",
      "Cayman Islands",
      "Central African Republic",
      "Chad",
      "Channel Islands",
      "Chile",
      "China",
      "Christmas Island",
      "Cocos Island",
      "Colombia",
      "Comoros",
      "Congo",
      "Cook Islands",
      "Costa Rica",
      "Cote DIvoire",
      "Croatia",
      "Cuba",
      "Curaco",
      "Cyprus",
      "Czech Republic",
      "Denmark",
      "Djibouti",
      "Dominica",
      "Dominican Republic",
      "East Timor",
      "Ecuador",
      "Egypt",
      "El Salvador",
      "Equatorial Guinea",
      "Eritrea",
      "Estonia",
      "Ethiopia",
      "Falkland Islands",
      "Faroe Islands",
      "Fiji",
      "Finland",
      "France",
      "French Guiana",
      "French Polynesia",
      "French Southern Ter",
      "Gabon",
      "Gambia",
      "Georgia",
      "Germany",
      "Ghana",
      "Gibraltar",
      "Great Britain",
      "Greece",
      "Greenland",
      "Grenada",
      "Guadeloupe",
      "Guam",
      "Guatemala",
      "Guinea",
      "Guyana",
      "Haiti",
      "Hawaii",
      "Honduras",
      "Hong Kong",
      "Hungary",
      "Iceland",
      "Indonesia",
      "India",
      "Iran",
      "Iraq",
      "Ireland",
      "Isle of Man",
      "Israel",
      "Italy",
      "Jamaica",
      "Japan",
      "Jordan",
      "Kazakhstan",
      "Kenya",
      "Kiribati",
      "Korea North",
      "Korea Sout",
      "Kuwait",
      "Kyrgyzstan",
      "Laos",
      "Latvia",
      "Lebanon",
      "Lesotho",
      "Liberia",
      "Libya",
      "Liechtenstein",
      "Lithuania",
      "Luxembourg",
      "Macau",
      "Macedonia",
      "Madagascar",
      "Malaysia",
      "Malawi",
      "Maldives",
      "Mali",
      "Malta",
      "Marshall Islands",
      "Martinique",
      "Mauritania",
      "Mauritius",
      "Mayotte",
      "Mexico",
      "Midway Islands",
      "Moldova",
      "Monaco",
      "Mongolia",
      "Montserrat",
      "Morocco",
      "Mozambique",
      "Myanmar",
      "Nambia",
      "Nauru",
      "Nepal",
      "Netherland Antilles",
      "Netherlands",
      "Nevis",
      "New Caledonia",
      "New Zealand",
      "Nicaragua",
      "Niger",
      "Nigeria",
      "Niue",
      "Norfolk Island",
      "Norway",
      "Oman",
      "Pakistan",
      "Palau Island",
      "Palestine",
      "Panama",
      "Papua New Guinea",
      "Paraguay",
      "Peru",
      "Phillipines",
      "Pitcairn Island",
      "Poland",
      "Portugal",
      "Puerto Rico",
      "Qatar",
      "Republic of Montenegro",
      "Republic of Serbia",
      "Reunion",
      "Romania",
      "Russia",
      "Rwanda",
      "St Barthelemy",
      "St Eustatius",
      "St Helena",
      "St Kitts-Nevis",
      "St Lucia",
      "St Maarten",
      "St Pierre & Miquelon",
      "St Vincent & Grenadines",
      "Saipan",
      "Samoa",
      "Samoa American",
      "San Marino",
      "Sao Tome & Principe",
      "Saudi Arabia",
      "Senegal",
      "Seychelles",
      "Sierra Leone",
      "Singapore",
      "Slovakia",
      "Slovenia",
      "Solomon Islands",
      "Somalia",
      "South Africa",
      "Spain",
      "Sri Lanka",
      "Sudan",
      "Suriname",
      "Swaziland",
      "Sweden",
      "Switzerland",
      "Syria",
      "Tahiti",
      "Taiwan",
      "Tajikistan",
      "Tanzania",
      "Thailand",
      "Togo",
      "Tokelau",
      "Tonga",
      "Trinidad & Tobago",
      "Tunisia",
      "Turkey",
      "Turkmenistan",
      "Turks & Caicos Is",
      "Tuvalu",
      "Uganda",
      "United Kingdom",
      "Ukraine",
      "United Arab Erimates",
      "United States of America",
      "Uraguay",
      "Uzbekistan",
      "Vanuatu",
      "Vatican City State",
      "Venezuela",
      "Vietnam",
      "Virgin Islands (Brit)",
      "Virgin Islands (USA)",
      "Wake Island",
      "Wallis & Futana Is",
      "Yemen",
      "Zaire",
      "Zambia",
      "Zimbabwe"
    ]
  end

  def list_farms(user) do
    Repo.all(
      from f in Farm,
        join: fu in FarmUser,
        on:
          fu.user_id == ^user.id and
            f.id == fu.farm_id and
            fu.role != "disable",
        order_by: f.name,
        select: %{
          address1: f.address1,
          address2: f.address2,
          city: f.city,
          country: f.country,
          id: f.id,
          name: f.name,
          state: f.state,
          weight_unit: f.weight_unit,
          zipcode: f.zipcode,
          default_farm: fu.default_farm,
          role: fu.role
        }
    )
  end

  def get_farm!(id, user) do
    Repo.get!(
      from(f in Farm,
        join: fu in FarmUser,
        on:
          fu.user_id == ^user.id and
            f.id == fu.farm_id and
            fu.role != "disable",
        select: f,
        order_by: f.name
      ),
      id
    )
  end

  def get_farm(id, user) do
    Repo.get(
      from(f in Farm,
        join: fu in FarmUser,
        on:
          fu.user_id == ^user.id and
            f.id == fu.farm_id and
            fu.role != "disable",
        select: f,
        order_by: f.name
      ),
      id
    )
  end

  def get_farm_user(farm_id, user_id) do
    Repo.one(
      from(f in Farm,
        join: fu in FarmUser,
        on:
          fu.user_id == ^user_id and
            f.id == fu.farm_id and
            fu.farm_id == ^farm_id and
            fu.role != "disable",
        select: %{role: fu.role, farm_id: f.id, user_id: fu.user_id, farm: %{name: f.name}}
      )
    )
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
    case can?(user.id, :delete_farm, farm.id) do
      {:allow, _} ->
        Repo.delete(farm)

      {:forbid, msg} ->
        {:error, farm, msg}
    end
  end

  def set_default_farm(user_id, farm_id) do
    update_default_farm_query =
      from(fu in FarmUser,
        where: fu.farm_id == ^farm_id and fu.user_id == ^user_id
      )

    update_not_default_farm_query =
      from(fu in FarmUser,
        where: fu.farm_id != ^farm_id and fu.user_id == ^user_id
      )

    Multi.new()
    |> Multi.update_all(:default, update_default_farm_query, set: [default_farm: true])
    |> Multi.update_all(:not_default, update_not_default_farm_query, set: [default_farm: false])
    |> Peggy.Repo.transaction()
  end

  def get_default_farm(user) do
    Repo.one(
      from f in Farm,
        join: fu in FarmUser,
        on: fu.farm_id == f.id,
        where: fu.default_farm == true and fu.user_id == ^user.id,
        select: f
    )
  end

  def allow_user_access_farm(user_id, role, current_farm_user) do
    case can?(current_farm_user, :allow_farm_access_to, user_id) do
      {:allow, _} ->
        %FarmUser{}
        |> FarmUser.changeset(%{user_id: user_id, farm_id: current_farm_user.farm_id, role: role})
        |> Repo.insert()

      {:forbid, msg} ->
        {:error,
         FarmUser.changeset(%FarmUser{}, %{
           user_id: user_id,
           farm_id: current_farm_user.farm_id,
           role: role
         }), msg}
    end
  end

  def change_user_role_in_farm(user_id, role, current_farm_user) do
    case can?(current_farm_user, :change_role_of, user_id) do
      {:allow, _} ->
        fu = Repo.get_by(FarmUser, farm_id: current_farm_user.farm_id, user_id: user_id)

        fu =
          FarmUser.changeset(fu, %{role: role})
          |> Repo.update()

        Phoenix.PubSub.broadcast(
          Peggy.PubSub,
          "user_role_updated",
          {:log_out_user, %{farm_id: current_farm_user.farm_id, user_id: user_id}}
        )

        fu

      {:forbid, msg} ->
        {:error,
         FarmUser.changeset(%FarmUser{}, %{
           user_id: user_id,
           farm_id: current_farm_user.farm_id,
           role: role
         }), msg}
    end
  end

  def update_farm(%Farm{} = farm, attrs, user) do
    case can?(user.id, :update_farm, farm.id) do
      {:allow, _} ->
        farm
        |> Farm.changeset(attrs, user)
        |> Repo.update()

      {:forbid, msg} ->
        {:error, farm, msg}
    end
  end

  def change_farm(%Farm{} = farm, attrs \\ %{}, user) do
    Farm.changeset(farm, attrs, user)
  end

  def farm_users(farm_user) do
    case can?(farm_user, :see_user_list) do
      {:allow, _} ->
        Repo.all(
          from u in User,
            join: fu in FarmUser,
            on: fu.farm_id == ^farm_user.farm_id and u.id == fu.user_id,
            order_by: u.email,
            select: %{
              email: u.email,
              role: fu.role,
              id: u.id,
              last_log_in_at: u.last_log_in_at
            }
        )

      {:forbid, msg} ->
        []
    end
  end
end
