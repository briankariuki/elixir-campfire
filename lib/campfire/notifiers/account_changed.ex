defmodule Campfire.Notifiers.AccountChanged do
  @moduledoc """
  Tells every node that the account changed. Runs after the outermost transaction commits for
  each `Account` create, update and destroy (name, logo, custom styles, the restriction flag,
  `reset_join_code`, and the create inside `first_run`), and broadcasts `:account_changed` on
  the `"account"` topic. `Campfire.AccountCache` subscribes to it and drops its copy.

  Calls `Phoenix.PubSub` directly rather than `Campfire.PubSubBroadcaster`: nothing but the
  cache listens, and the message carries no data.
  """

  use Ash.Notifier

  alias Ash.Notifier.Notification

  @impl true
  def notify(%Notification{}) do
    Phoenix.PubSub.broadcast(Campfire.PubSub, Campfire.AccountCache.topic(), :account_changed)
    :ok
  end
end
