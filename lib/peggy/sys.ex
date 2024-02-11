defmodule Peggy.Sys do
  import Ecto.Query, warn: false
  import Peggy.Authorization
  import Peggy.Helpers

  alias Peggy.Repo
  alias Ecto.Multi
  alias Peggy.UserAccounts.User
  alias Peggy.Sys.Farm
  alias Peggy.Sys.FarmUser
  alias Peggy.Sys.Log

  def countries(), do: Enum.sort(Enum.map(Countries.all(), fn x -> "#{x.name}" end))

  def list_logs(entity, entity_id) do
    Repo.all(
      from log in Log,
        as: :logs,
        join: user in User,
        on: user.id == log.user_id,
        where: log.entity == ^entity,
        where: log.entity_id == ^entity_id,
        select: log,
        select_merge: %{email: user.email},
        order_by: log.inserted_at
    )
  end

  def get_farm!(id) do
    Repo.get!(Farm, id)
  end

  def user_farms(user) do
    from(c in Farm,
      join: cu in FarmUser,
      on: c.id == cu.farm_id,
      where: cu.user_id == ^user.id,
      where: cu.role != "disable"
    )
  end

  def user_farm(farm, user) do
    from(c in Farm,
      join: cu in FarmUser,
      on: c.id == cu.farm_id,
      where: cu.user_id == ^user.id,
      where: cu.role != "disable",
      where: c.id == ^farm.id,
      select: %{id: c.id}
    )
  end

  def get_farm_user(farm_id, user_id) do
    Repo.one(from(cu in FarmUser, where: cu.farm_id == ^farm_id, where: cu.user_id == ^user_id))
  end

  def get_farm_users(farm, user) do
    if can?(user, :see_user_list, farm) do
      Repo.all(
        from(u in User,
          join: cu in FarmUser,
          on: u.id == cu.user_id,
          where: cu.farm_id == ^farm.id,
          order_by: u.email,
          select: %{id: u.id, email: u.email, role: cu.role}
        )
      )
    else
      [
        Repo.one(
          from(u in User,
            join: cu in FarmUser,
            on: u.id == cu.user_id,
            where: cu.farm_id == ^farm.id,
            where: cu.user_id == ^user.id,
            select: %{id: u.id, email: u.email, role: cu.role}
          )
        )
      ]
    end
  end

  def get_default_farm(user) do
    Repo.one(
      from(cu in subquery(farms_query(user.id)),
        where: cu.default_farm == true
      )
    )
  end

  def list_farms(user) do
    Repo.all(farms_query(user.id))
  end

  defp farms_query(user_id) do
    from(c in Farm,
      join: cu in FarmUser,
      on: c.id == cu.farm_id,
      where: cu.user_id == ^user_id,
      where: cu.role != "disable",
      order_by: c.name,
      select: %{
        address1: c.address1,
        address2: c.address2,
        city: c.city,
        country: c.country,
        farm_id: cu.farm_id,
        user_id: cu.user_id,
        name: c.name,
        state: c.state,
        zipcode: c.zipcode,
        tel: c.tel,
        descriptions: c.descriptions,
        timezone: c.timezone,
        email: c.email,
        default_farm: cu.default_farm,
        role: cu.role,
        updated_at: c.updated_at,
        id: c.id
      }
    )
  end

  def create_farm(attrs \\ %{}, user) do
    Multi.new()
    |> Multi.insert(:create_farm, farm_changeset(%Farm{}, attrs, user))
    |> Multi.insert(:create_farm_user, fn %{create_farm: c} ->
      if Repo.aggregate(farms_query(user.id), :count) > 0,
        do:
          farm_user_changeset(%FarmUser{}, %{
            farm_id: c.id,
            user_id: user.id,
            role: "admin"
          }),
        else:
          farm_user_changeset(%FarmUser{}, %{
            farm_id: c.id,
            user_id: user.id,
            role: "admin",
            default_farm: true
          })
    end)
    |> Peggy.Repo.transaction()
    |> case do
      {:ok, %{create_farm: farm}} ->
        {:ok, farm}

      {:error, failed_operation, failed_value, changes_so_far} ->
        {:error, failed_operation, failed_value, changes_so_far}
    end
  end

  def update_farm(farm, attrs \\ %{}, user) do
    case can?(user, :update_farm, farm) do
      true ->
        Multi.new()
        |> Multi.update(:update_farm, farm_changeset(farm, attrs, user))
        |> Peggy.Repo.transaction()
        |> case do
          {:ok, %{update_farm: farm}} ->
            {:ok, farm}

          {:error, failed_operation, failed_value, changes_so_far} ->
            {:error, failed_operation, failed_value, changes_so_far}
        end

      false ->
        :not_authorise
    end
  end

  def delete_farm(farm, user) do
    case can?(user, :delete_farm, farm) do
      true ->
        Multi.new()
        |> Multi.delete(:delete_farm, farm)
        |> Peggy.Repo.transaction()
        |> case do
          {:ok, %{delete_farm: farm}} ->
            {:ok, farm}

          {:error, failed_operation, failed_value, changes_so_far} ->
            {:error, failed_operation, failed_value, changes_so_far}
        end

      false ->
        :not_authorise
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
    |> case do
      {:ok, %{default: farm}} ->
        {:ok, farm}

      {:error, failed_operation, failed_value, changes_so_far} ->
        {:error, failed_operation, failed_value, changes_so_far}
    end
  end

  def allow_user_to_access(com, user, role, admin) do
    case can?(admin, :add_user_to_farm, com) do
      true ->
        case Repo.insert(
               farm_user_changeset(%FarmUser{}, %{
                 farm_id: com.id,
                 user_id: user.id,
                 role: role
               })
             ) do
          {:ok, struct} -> {:ok, struct}
          {:error, changeset} -> {:error, changeset}
        end

      false ->
        :not_authorise
    end
  end

  def delete_user_from_farm(com, user, admin) do
    case can?(admin, :delete_user_from_farm, com) and admin != user do
      true ->
        uc = get_farm_user(com.id, user.id)

        if uc do
          Repo.delete(uc)
        end

      false ->
        :not_authorise
    end
  end

  def add_user_to_farm(com, email, role, admin) do
    case can?(admin, :add_user_to_farm, com) do
      true ->
        user = Peggy.UserAccounts.get_user_by_email(email)

        if user do
          case allow_user_to_access(com, user, role, admin) do
            {:ok, cu} -> {:ok, {user, cu, nil}}
            {:error, cs} -> {:error, cs}
          end
        else
          pwd = gen_temp_id(12)

          Multi.new()
          |> Multi.insert(
            :register_user,
            User.admin_add_user_changeset(%User{}, %{
              email: email,
              password: pwd,
              password_confirmation: pwd,
              farm_id: com.id
            })
          )
          |> Multi.insert(:allow_user_access_farm, fn %{register_user: u} ->
            farm_user_changeset(%FarmUser{}, %{
              farm_id: com.id,
              user_id: u.id,
              role: role,
              default_farm: if(role == "punch_camera", do: true, else: false)
            })
          end)
          |> Peggy.Repo.transaction()
          |> case do
            {:ok, %{register_user: user, allow_user_access_farm: cu}} -> {:ok, {user, cu, pwd}}
            {:error, fail_at, fail_value, _} -> {:error, fail_at, fail_value}
          end
        end

      false ->
        :not_authorise
    end
  end

  def change_user_role_in(com, user_id, role, admin) do
    case can?(admin, :change_user_role, com, %{id: user_id}) do
      true ->
        com_user = get_farm_user(com.id, user_id)

        Repo.update(
          farm_user_changeset(com_user, %{
            role: role
          })
        )

      false ->
        :not_authorise
    end
  end

  def reset_user_password(user, admin, com) do
    case can?(admin, :reset_user_password, com) do
      true ->
        pwd = gen_temp_id(12)

        changeset =
          user
          |> User.password_changeset(%{"password" => pwd, "password_confirmation" => pwd})

        Ecto.Multi.new()
        |> Ecto.Multi.update(:user, changeset)
        |> Ecto.Multi.delete_all(:tokens, Peggy.UserAccounts.UserToken.by_user_and_contexts_query(user, :all))
        |> Repo.transaction()
        |> case do
          {:ok, %{user: user}} ->
            {:ok, user, pwd}

          {:error, :user, changeset, _} ->
            {:error, changeset}
        end

      false ->
        :not_authorise
    end
  end

  def insert_log_for(multi, name, entity_attrs, farm, user) do
    Ecto.Multi.insert(multi, "#{name}_log", fn %{^name => entity} ->
      log_changeset(name, entity, entity_attrs, farm, user)
    end)
  end

  def log_entry_for(entity, entity_id, farm_id) do
    Repo.all(
      from(log in Log,
        where: log.farm_id == ^farm_id,
        where: log.entity == ^entity,
        where: log.entity_id == ^entity_id,
        order_by: log.inserted_at
      )
    )
  end

  def log_changeset(name, entity, entity_attrs, farm, user) do
    Log.changeset(%Log{}, log_attrs(name, entity, entity_attrs, farm, user))
  end

  def log_attrs(name, entity, entity_attrs, farm, user) do
    %{
      entity: entity.__meta__.source,
      entity_id: entity.id,
      action: Atom.to_string(name),
      delta: attr_to_string(entity_attrs),
      user_id: user.id,
      farm_id: farm.id
    }
  end

  def attr_to_string(attrs) do
    bl = ["_id", "delete", "__meta__"]

    if Enum.any?(attrs, fn {k, v} ->
         (k == "delete" or k == :delete) and v == "true"
       end) do
      ""
    else
      attrs
      |> Enum.map(fn {k, v} ->
        k = if(is_atom(k), do: Atom.to_string(k), else: k)

        if !String.ends_with?(k, bl) and k != "id" do
          if !is_map(v) do
            if v != "" and !is_nil(v),
              do: "&^#{k}: #{Phoenix.HTML.html_escape(v) |> Phoenix.HTML.safe_to_string()}^&",
              else: nil
          else
            "&^#{k}: [" <> attr_to_string(v) <> "]^&"
          end
        end
      end)
      |> Enum.reject(fn x -> is_nil(x) end)
      |> Enum.join(" ")
    end
  end

  def farm_changeset(farm, attrs \\ %{}, user) do
    Farm.changeset(farm, attrs, user)
  end

  def farm_user_changeset(farm_user, attrs \\ %{}) do
    FarmUser.changeset(farm_user, attrs)
  end

  def get_user_default_farm_by_email(email) do
    u = Peggy.UserAccounts.get_user_by_email(email)
    c = get_default_farm(u)
    {u, c}
  end

  def get_rouge_users(com, user) do
    if can?(user, :manage_rouge_user, com) do
      td = Timex.today()

      from(u in User,
        where: u.id not in subquery(from(cu in FarmUser, select: cu.user_id)),
        where: fragment("(?::date - ?::date) >= 5", ^td, u.inserted_at),
        where: is_nil(u.confirmed_at)
      )
      |> Repo.all()
    else
      []
    end
  end

  def delete_rouge_user(com, rouge_user, user) do
    if can?(user, :manage_rouge_user, com) do
      u = Repo.get!(User, rouge_user.id)

      if u do
        Repo.delete(u)
      end
    else
      :not_authorise
    end
  end
end
