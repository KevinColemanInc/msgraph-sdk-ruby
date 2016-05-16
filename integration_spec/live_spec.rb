require_relative "integration_spec_helper"

describe MicrosoftGraph::User do
  Given(:auth_callback) {
    Proc.new { |r| r.headers["Authorization"] = "Bearer #{TOKENS.access_token}" }
  }
  Given(:test_run_id) { rand(2**128) }
  Given(:graph) { MicrosoftGraph.new(&auth_callback) }
  Given(:user) { graph.users.take(3).last }
  Given(:email_destination) { user.user_principal_name }
  Given(:message_template) {
    {
      subject: "test message #{test_run_id}",
      body: {
        content: "Hello.\n\nThis message is generated by an automated test suite.",
      },
      to_recipients: [
        { email_address: { address: email_destination } },
      ],
    }
  }

  describe 'current user' do
    Given(:subject) { graph.me }

    describe 'direct reports' do
      When(:result) { subject.direct_reports.take(5) }
      Then { result.length == 0 }
    end

    describe 'membership' do
      Given(:groups) { subject.member_of.take(5) }
      Given(:group) { groups.last }

      When(:result) { subject.check_member_groups(group_ids: [group.id]) }

      Then { result.to_a == [group.id] }
      And  { groups.length == 5 }
      And  { group.display_name.length > 0 }
    end

    describe MicrosoftGraph::Drive do
      Given(:drive) { subject.drive }

      describe MicrosoftGraph::DriveItem do
        Given(:root) { drive.root }
        Given(:root_contents) { root.children }

        Then { root_contents.size == 0 }
      end
    end

    describe 'contacts' do
      Given(:contacts) { subject.contacts.take(5) }
      Given(:contact) { contacts.last }

      Then { contacts.to_a.size == 5 }
      And  { contact.display_name.length > 0 }
    end

    describe 'email' do
      describe 'send a new email' do
        When(:result) { subject.send_mail(message: message_template) }
        Then { result != Failure() }
      end
    end

    describe 'messages' do
      Given(:messages) { subject.mail_folders.find('Inbox').messages }
      Given(:first_five_messages) { messages.take(5) }
      Given(:message) { first_five_messages.last }

      describe 'list' do
        When(:result) { first_five_messages.size }
        Then { result == 5 }
      end

      describe 'post a reply' do
        When(:result) { message.create_reply('test reply') }
        Then { result != Failure() }
      end

      describe 'post a reply-all' do
        When(:result) { message.create_reply_all('test reply-all') }
        Then { result != Failure() }
      end

      describe 'drafts' do
        Given(:draft_messages) { subject.mail_folders.find('Drafts').messages }
        # Note: Graph API seems to not allow you to find a mail_folder with a space in its name like we do above
        Given(:sent_messages) { subject.mail_folders.detect { |f| f.display_name == 'Sent Items' }.messages }

        describe 'post and send a draft message' do
          When(:draft_message) { draft_messages.create!(message_template) }
          When(:draft_id) { draft_message.id }
          When(:draft_title) { draft_message.subject }
          When(:send_result) { draft_message.send }
          When { sleep 0.5 }
          When(:try_finding_in_drafts) { draft_messages.find(draft_id) }
          # below could find the wrong message if someone else is sending at the same time:
          When(:sent_message) { sent_messages.order_by('sentDateTime desc').first }
          When(:sent_title) { sent_message.subject }

          Then { send_result != Failure() }
          And  { try_finding_in_drafts == Failure(OData::ClientError, /404/) }
          And  { sent_title == draft_title }
        end
      end
    end

    describe 'calendar' do
      Given(:calendar) { subject.calendar }
      Given(:event_template) {
        {
          subject: 'test event',
          body: {
            content: 'this event generated by an automated test suite'
          },
        }
      }

      describe 'events' do
        Given(:events) { calendar.events }

        describe 'new' do

          describe 'create!' do
            When(:event) { events.create!(event_template) }
            When(:id) { event.id }
            When(:title) { event.subject }
            When { event.delete! }
            When(:get_deleted_event) { events.find(id) }

            Then { title == event_template[:subject] }
            And  { get_deleted_event == Failure(OData::ClientError, /404/) }
          end

          describe 'create recurring' do
            Given(:start_date) { Date.today }
            Given(:recurring_event_template) {
              event_template.merge(
                recurrence: {
                  pattern: {
                    days_of_week: [start_date.strftime('%A').downcase],
                    interval: 1,
                    type: 'weekly',
                  },
                  range: {
                    start_date: start_date,
                    type: 'noEnd',
                  },
                }
              )
            }
            When(:event) { events.create!(recurring_event_template) }
            When(:id) { event.id }
            When(:title) { event.subject }
            When { event.delete! }
            When(:get_deleted_event) { events.find(id) }

            Then { id.length > 0 }
            And  { title == event_template[:subject] }
            And  { get_deleted_event == Failure(OData::ClientError, /404/) }
          end

          describe 'add attachment'
        end

        describe 'existing' do
          describe 'first invitation' do
            describe 'tentatively accept'
            describe 'accept'
            describe 'decline'
          end
        end
      end
    end
  end

end
