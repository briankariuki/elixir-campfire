defmodule CampfireWeb.ErrorMessages do
  @moduledoc "Turns Ash errors into short messages for flashes."

  @doc "A one-line, human readable summary of an error."
  def summary(%Ash.Error.Forbidden{}), do: "You're not allowed to do that."

  def summary(%{errors: [_ | _] = errors}) do
    errors |> Enum.map(&summary/1) |> Enum.uniq() |> Enum.join(". ")
  end

  def summary(%{field: field, message: message} = error)
      when is_atom(field) and not is_nil(field) and is_binary(message) do
    "#{humanize(field)} #{interpolate(message, Map.get(error, :vars, []))}"
  end

  def summary(%{message: message} = error) when is_binary(message) do
    interpolate(message, Map.get(error, :vars, []))
  end

  def summary(error) when is_exception(error), do: Exception.message(error)
  def summary(_error), do: "Something went wrong."

  @doc "Whether an Ash error is about `field`, e.g. a taken email address."
  def field_error?(%{errors: errors}, field) when is_list(errors),
    do: Enum.any?(errors, &field_error?(&1, field))

  def field_error?(%{field: field}, field), do: true
  def field_error?(_error, _field), do: false

  @doc """
  Whether a submitted `AshPhoenix.Form` (as a `Phoenix.HTML.Form`) failed because the actor isn't
  allowed to run the action, rather than because of invalid input.
  """
  def forbidden?(%Phoenix.HTML.Form{source: %AshPhoenix.Form{source: %{errors: errors}}}),
    do: Enum.any?(errors, &(Map.get(&1, :class) == :forbidden))

  def forbidden?(_form), do: false

  defp humanize(field) do
    field |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp interpolate(message, vars) do
    Enum.reduce(List.wrap(vars), message, fn
      {key, value}, acc when is_binary(value) or is_number(value) or is_atom(value) ->
        String.replace(acc, "%{#{key}}", to_string(value))

      _, acc ->
        acc
    end)
  end
end
