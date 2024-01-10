if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) do
  defmodule PolymorphicEmbed.HTML.Helpers do
    @doc """
    Returns the polymorphic type of the given field in the given form data.
    """
    def get_polymorphic_type(%Phoenix.HTML.Form{} = form, schema, field) do
      case form[field] && form[field].value do
        %Ecto.Changeset{data: value} ->
          PolymorphicEmbed.get_polymorphic_type(schema, field, value)

        %_{} = value ->
          PolymorphicEmbed.get_polymorphic_type(schema, field, value)

        %{} = map ->
          case PolymorphicEmbed.get_polymorphic_module(schema, field, map) do
            nil ->
              nil

            module ->
              PolymorphicEmbed.get_polymorphic_type(schema, field, module)
          end

        list when is_list(list) ->
          nil

        nil ->
          nil
      end
    end

    def to_form(%{action: parent_action} = source_changeset, form, field, type, options) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params || %{}, to_string(field), %{}) |> List.wrap()
      list_data = get_data(source_changeset, field, type) |> List.wrap()
      num_entries = length(list_data)

      list_data
      |> Enum.with_index()
      |> Enum.map(fn {data, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          data
          |> Ecto.Changeset.change()
          |> apply_action(parent_action)

        errors = get_errors(changeset)

        changeset = %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }

        index_string = Integer.to_string(i)
        # get the source schema for fetching the type if it was not determined earlier
        # and also correctly set id and name for embeds_many inputs
        %schema{} = form.source.data
        field_options = PolymorphicEmbed.get_field_options(schema, field)
        type_field = Map.fetch!(field_options, :type_field_atom)
        array? = Map.get(field_options, :array?, false)
        type = type || PolymorphicEmbed.get_polymorphic_type(schema, field, changeset.data)

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          # https://github.com/phoenixframework/phoenix_ecto/blob/ae8112822152ac206764c33fdc53ede0e60bbcbb/lib/phoenix_ecto/html.ex#L92
          id: if(num_entries > 1 || array?, do: id <> "_" <> index_string, else: id),
          name: if(num_entries > 1 || array?, do: name <> "[" <> index_string <> "]", else: name),
          index: if(num_entries > 1 || array?, do: i),
          errors: errors,
          data: data,
          params: params,
          hidden: [{type_field, to_string(type)}],
          options: options
        }
      end)
    end

    defp get_data(changeset, field, type) do
      struct = Ecto.Changeset.apply_changes(changeset)

      case Map.get(struct, field) do
        nil ->
          module = PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type)
          if module, do: struct(module), else: []

        data ->
          data
      end
    end

    # If the parent changeset had no action, we need to remove the action
    # from children changeset so we ignore all errors accordingly.
    defp apply_action(changeset, nil), do: %{changeset | action: nil}
    defp apply_action(changeset, _action), do: changeset

    defp get_errors(%{action: nil}), do: []
    defp get_errors(%{action: :ignore}), do: []
    defp get_errors(%{errors: errors}), do: errors
  end
end
