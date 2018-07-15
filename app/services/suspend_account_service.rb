# frozen_string_literal: true

class SuspendAccountService < BaseService
  def call(account, remove_user = false)
    @account = account

    purge_user if remove_user
    purge_profile
    purge_content
    unsubscribe_push_subscribers
  end

  private

  def purge_user
    @account.user.destroy
  end

  def purge_content
    @account.statuses.reorder(nil).find_in_batches(batch_size: 100).with_index(1) do |statuses, batch_index|
      BatchedRemoveStatusService.new.call(statuses, batch_index)
    end

    [
      @account.media_attachments,
      @account.stream_entries,
      @account.notifications,
      @account.favourites,
      @account.active_relationships,
      @account.passive_relationships,
    ].each do |association|
      destroy_all(association)
    end
  end

  def purge_profile!
    @account.suspended      = true
    @account.display_name   = ''
    @account.note           = ''
    @account.statuses_count = 0
    @account.avatar.destroy
    @account.header.destroy
    @account.save!
  end

  def unsubscribe_push_subscribers
    destroy_all(@account.subscriptions)
  end

  def destroy_all(association)
    association.in_batches.destroy_all
  end

  def delete_actor_json
    payload = ActiveModelSerializers::SerializableResource.new(
      @account,
      serializer: ActivityPub::DeleteActorSerializer,
      adapter: ActivityPub::Adapter
    ).as_json

    Oj.dump(ActivityPub::LinkedDataSignature.new(payload).sign!(@account))
  end
end

